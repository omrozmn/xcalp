import Foundation
import Metal
import MetalKit
import simd

/// Handles 3D mesh processing and optimization
public final class MeshProcessor {
    public static let shared = MeshProcessor()
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState?
    private let compressionService = CompressionService.shared
    private let maxUncompressedSize: UInt64 = 100 * 1024 * 1024 // 100MB
    private let validation = ValidationSystem.shared
    private let monitor = PerformanceMonitor.shared
    
    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.commandQueue = commandQueue
        setupComputePipeline()
    }
    
    private func setupComputePipeline() {
        let library = try? device.makeDefaultLibrary()
        let kernelFunction = library?.makeFunction(name: "processMeshKernel")
        
        do {
            computePipelineState = try device.makeComputePipelineState(function: kernelFunction!)
        } catch {
            print("Failed to create compute pipeline: \(error)")
        }
    }
    
    /// Processes raw scan data into optimized 3D mesh
    public func processMesh(_ scanData: Data) async throws -> ProcessedMesh {
        let perfID = monitor.startMeasuring("meshProcessing", category: "processing")
        defer { monitor.endMeasuring("meshProcessing", signpostID: perfID) }
        
        // Generate hash for validation
        let originalHash = SHA256.hash(data: scanData)
        
        // Compress data if it's too large
        let dataToProcess: Data
        let originalSize = scanData.count
        if scanData.count > maxUncompressedSize {
            dataToProcess = try compressionService.compressData(scanData)
        } else {
            dataToProcess = scanData
        }
        
        // Create buffers with optimized size
        let vertexCount = originalSize / MemoryLayout<SIMD3<Float>>.stride
        let bufferSize = min(UInt64(vertexCount * MemoryLayout<SIMD3<Float>>.stride), maxUncompressedSize)
        
        guard let vertexBuffer = device.makeBuffer(length: Int(bufferSize)),
              let normalBuffer = device.makeBuffer(length: Int(bufferSize)),
              let indexBuffer = device.makeBuffer(length: vertexCount * MemoryLayout<UInt32>.size) else {
            throw ProcessingError.bufferCreationFailed
        }
        
        // Process data in chunks if needed
        if dataToProcess.count > maxUncompressedSize {
            return try await processLargeMesh(dataToProcess, originalHash: Data(originalHash))
        }
        
        // Copy data to buffer
        dataToProcess.withUnsafeBytes { ptr in
            vertexBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: dataToProcess.count)
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.commandEncodingFailed
        }
        
        computeEncoder.setComputePipelineState(computePipelineState!)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 2)
        
        // Calculate thread groups
        let threadsPerGroup = MTLSize(width: 512, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (vertexCount + 511) / 512,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Extract processed data
        var vertices: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        var normals: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        var indices: [UInt32] = Array(repeating: 0, count: vertexCount)
        
        memcpy(&vertices, vertexBuffer.contents(), vertexCount * MemoryLayout<SIMD3<Float>>.stride)
        memcpy(&normals, normalBuffer.contents(), vertexCount * MemoryLayout<SIMD3<Float>>.stride)
        memcpy(&indices, indexBuffer.contents(), vertexCount * MemoryLayout<UInt32>.stride)
        
        let processedMesh = ProcessedMesh(
            vertices: vertices,
            normals: normals,
            indices: indices,
            quality: validateMeshQuality(vertices: vertices, normals: normals)
        )
        
        // Validate the processed mesh
        try validation.validateMeshQuality(processedMesh)
        
        // Track metrics
        monitor.trackMetric("vertexCount", value: Double(processedMesh.vertices.count))
        monitor.trackMetric("processingTime", value: monitor.measurementDuration(signpostID: perfID))
        
        return processedMesh
    }
    
    private func processLargeMesh(_ compressedData: Data, originalHash: Data) async throws -> ProcessedMesh {
        let chunkSize = Int(maxUncompressedSize)
        let decompressedData = try compressionService.decompressData(compressedData, expectedSize: originalHash.count)
        
        var processedVertices: [SIMD3<Float>] = []
        var processedNormals: [SIMD3<Float>] = []
        var processedIndices: [UInt32] = []
        
        for chunkStart in stride(from: 0, to: decompressedData.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, decompressedData.count)
            let chunk = decompressedData[chunkStart..<chunkEnd]
            
            let chunkMesh = try await processChunk(Data(chunk))
            processedVertices.append(contentsOf: chunkMesh.vertices)
            processedNormals.append(contentsOf: chunkMesh.normals)
            
            // Adjust indices for the merged mesh
            let indexOffset = UInt32(chunkStart / MemoryLayout<SIMD3<Float>>.stride)
            processedIndices.append(contentsOf: chunkMesh.indices.map { $0 + indexOffset })
        }
        
        let processedMesh = ProcessedMesh(
            vertices: processedVertices,
            normals: processedNormals,
            indices: processedIndices,
            quality: validateMeshQuality(vertices: processedVertices, normals: processedNormals)
        )
        
        // Validate processed data
        try validation.validateProcessedData(processedMesh, originalHash: originalHash)
        
        return processedMesh
    }
    
    private func processChunk(_ chunkData: Data) async throws -> ProcessedMesh {
        // Monitor resource usage
        let memoryUsage = ProcessInfo.processInfo.physicalMemory
        let availableMemory = ProcessInfo.processInfo.physicalMemory - mach_task_self_.memoryUsage()
        
        guard availableMemory > UInt64(chunkData.count * 3) else {
            throw ProcessingError.insufficientMemory(available: availableMemory)
        }
        
        // Existing processing logic for a single chunk
        let vertexCount = chunkData.count / MemoryLayout<SIMD3<Float>>.stride
        
        // Create buffers
        guard let vertexBuffer = device.makeBuffer(length: chunkData.count),
              let normalBuffer = device.makeBuffer(length: chunkData.count),
              let indexBuffer = device.makeBuffer(length: vertexCount * MemoryLayout<UInt32>.size) else {
            throw ProcessingError.bufferCreationFailed
        }
        
        // Copy scan data to vertex buffer
        chunkData.withUnsafeBytes { ptr in
            vertexBuffer.contents().copyMemory(from: ptr.baseAddress!, byteCount: chunkData.count)
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.commandEncodingFailed
        }
        
        computeEncoder.setComputePipelineState(computePipelineState!)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 2)
        
        // Calculate thread groups
        let threadsPerGroup = MTLSize(width: 512, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (vertexCount + 511) / 512,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Extract processed data
        var vertices: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        var normals: [SIMD3<Float>] = Array(repeating: .zero, count: vertexCount)
        var indices: [UInt32] = Array(repeating: 0, count: vertexCount)
        
        memcpy(&vertices, vertexBuffer.contents(), vertexCount * MemoryLayout<SIMD3<Float>>.stride)
        memcpy(&normals, normalBuffer.contents(), vertexCount * MemoryLayout<SIMD3<Float>>.stride)
        memcpy(&indices, indexBuffer.contents(), vertexCount * MemoryLayout<UInt32>.stride)
        
        return ProcessedMesh(
            vertices: vertices,
            normals: normals,
            indices: indices,
            quality: validateMeshQuality(vertices: vertices, normals: normals)
        )
    }
    
    /// Optimizes mesh for rendering
    public func optimizeMesh(_ mesh: ProcessedMesh) async throws -> ProcessedMesh {
        // Implement mesh decimation and optimization
        let optimizedVertices = await decimateMesh(
            vertices: mesh.vertices,
            normals: mesh.normals,
            indices: mesh.indices,
            targetReduction: 0.5
        )
        
        return ProcessedMesh(
            vertices: optimizedVertices.vertices,
            normals: optimizedVertices.normals,
            indices: optimizedVertices.indices,
            quality: mesh.quality
        )
    }
    
    /// Validates mesh quality
    public func validateMeshQuality(_ mesh: ProcessedMesh) -> MeshQuality {
        validateMeshQuality(vertices: mesh.vertices, normals: mesh.normals)
    }
    
    private func validateMeshQuality(vertices: [SIMD3<Float>], normals: [SIMD3<Float>]) -> MeshQuality {
        let vertexCount = vertices.count
        guard vertexCount > 0 else { return .poor }
        
        // Calculate mesh density
        var boundingBox = (min: vertices[0], max: vertices[0])
        for vertex in vertices {
            boundingBox.min = simd_min(boundingBox.min, vertex)
            boundingBox.max = simd_max(boundingBox.max, vertex)
        }
        
        let volume = (boundingBox.max - boundingBox.min).reduce(1, *)
        let density = Float(vertexCount) / volume
        
        // Calculate normal consistency
        var normalConsistency: Float = 0
        for i in 0..<(vertexCount - 1) {
            normalConsistency += abs(simd_dot(normals[i], normals[i + 1]))
        }
        normalConsistency /= Float(vertexCount - 1)
        
        // Evaluate quality based on metrics
        if density < 100 || normalConsistency < 0.3 {
            return .poor
        } else if density < 500 || normalConsistency < 0.6 {
            return .acceptable
        } else if density < 1000 || normalConsistency < 0.8 {
            return .good
        } else {
            return .excellent
        }
    }
    
    private func decimateMesh(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        indices: [UInt32],
        targetReduction: Float
    ) async -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        // Calculate target vertex count
        let targetCount = Int(Float(vertices.count) * (1 - targetReduction))
        
        // Create quadric error metrics for each vertex
        var quadrics = vertices.map { _ -> matrix_float4x4 in
            var q = matrix_float4x4.zero
            
            // Calculate quadric from adjacent faces
            for i in stride(from: 0, to: indices.count, by: 3) {
                let v1 = vertices[Int(indices[i])]
                let v2 = vertices[Int(indices[i + 1])]
                let v3 = vertices[Int(indices[i + 2])]
                
                // Calculate face normal and distance
                let normal = normalize(cross(v2 - v1, v3 - v1))
                let d = -dot(normal, v1)
                
                // Create plane equation [a b c d]
                let plane = SIMD4<Float>(normal.x, normal.y, normal.z, d)
                
                // Calculate quadric matrix
                let p = plane
                q += matrix_float4x4(
                    SIMD4<Float>(p.x * p.x, p.x * p.y, p.x * p.z, p.x * p.w),
                    SIMD4<Float>(p.y * p.x, p.y * p.y, p.y * p.z, p.y * p.w),
                    SIMD4<Float>(p.z * p.x, p.z * p.y, p.z * p.z, p.z * p.w),
                    SIMD4<Float>(p.w * p.x, p.w * p.y, p.w * p.z, p.w * p.w)
                )
            }
            
            return q
        }
        
        // Create edge collapse costs
        var costs: [(v1: Int, v2: Int, cost: Float, position: SIMD3<Float>)] = []
        for i in 0..<vertices.count {
            for j in (i + 1)..<vertices.count {
                if let (cost, position) = calculateEdgeCollapseCost(
                    v1: i,
                    v2: j,
                    vertices: vertices,
                    quadrics: quadrics
                ) {
                    costs.append((i, j, cost, position))
                }
            }
        }
        
        // Sort costs
        costs.sort { $0.cost < $1.cost }
        
        // Track valid vertices and create mapping
        var validVertices = Array(repeating: true, count: vertices.count)
        var vertexMapping = Array(0..<vertices.count)
        var newVertices = vertices
        var newNormals = normals
        var currentCount = vertices.count
        
        // Perform edge collapses
        for collapse in costs {
            if currentCount <= targetCount { break }
            if !validVertices[collapse.v1] || !validVertices[collapse.v2] { continue }
            
            // Perform collapse
            newVertices[collapse.v1] = collapse.position
            validVertices[collapse.v2] = false
            vertexMapping[collapse.v2] = collapse.v1
            
            // Merge quadrics
            quadrics[collapse.v1] += quadrics[collapse.v2]
            
            // Update normal
            newNormals[collapse.v1] = normalize(newNormals[collapse.v1] + newNormals[collapse.v2])
            
            currentCount -= 1
        }
        
        // Build final mesh
        var finalVertices: [SIMD3<Float>] = []
        var finalNormals: [SIMD3<Float>] = []
        var finalIndices: [UInt32] = []
        var oldToNewMapping: [Int: Int] = [:]
        
        // Create new vertex arrays
        for i in 0..<vertices.count {
            if validVertices[i] {
                oldToNewMapping[i] = finalVertices.count
                finalVertices.append(newVertices[i])
                finalNormals.append(newNormals[i])
            }
        }
        
        // Remap indices
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            // Map to collapsed vertices
            let v1 = vertexMapping[i1]
            let v2 = vertexMapping[i2]
            let v3 = vertexMapping[i3]
            
            // Skip degenerate triangles
            if v1 == v2 || v2 == v3 || v3 == v1 { continue }
            
            // Add remapped indices
            if let n1 = oldToNewMapping[v1],
               let n2 = oldToNewMapping[v2],
               let n3 = oldToNewMapping[v3] {
                finalIndices.append(UInt32(n1))
                finalIndices.append(UInt32(n2))
                finalIndices.append(UInt32(n3))
            }
        }
        
        return (finalVertices, finalNormals, finalIndices)
    }
    
    private func calculateEdgeCollapseCost(
        v1: Int,
        v2: Int,
        vertices: [SIMD3<Float>],
        quadrics: [matrix_float4x4]
    ) -> (cost: Float, position: SIMD3<Float>)? {
        let q = quadrics[v1] + quadrics[v2]
        
        // Try to solve for optimal position
        var position: SIMD3<Float>
        
        // Extract upper 3x3 matrix and solve
        var a = matrix_float3x3(
            SIMD3<Float>(q[0][0], q[0][1], q[0][2]),
            SIMD3<Float>(q[1][0], q[1][1], q[1][2]),
            SIMD3<Float>(q[2][0], q[2][1], q[2][2])
        )
        
        // Check if matrix is invertible
        let det = a[0][0] * (a[1][1] * a[2][2] - a[2][1] * a[1][2]) -
                 a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
                 a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        
        if abs(det) > 1e-10 {
            // Matrix is invertible, solve for optimal position
            let b = SIMD3<Float>(-q[0][3], -q[1][3], -q[2][3])
            position = solveSystem(a, b)
        } else {
            // Use midpoint if matrix is not invertible
            position = (vertices[v1] + vertices[v2]) * 0.5
        }
        
        // Calculate cost using quadric error metric
        let v = SIMD4<Float>(position.x, position.y, position.z, 1)
        let cost = dot(v, q * v)
        
        return (cost, position)
    }
    
    private func solveSystem(_ a: matrix_float3x3, _ b: SIMD3<Float>) -> SIMD3<Float> {
        let det = determinant(a)
        let invDet = 1.0 / det
        
        let invA = matrix_float3x3(
            SIMD3<Float>(
                (a[1][1] * a[2][2] - a[1][2] * a[2][1]) * invDet,
                (a[0][2] * a[2][1] - a[0][1] * a[2][2]) * invDet,
                (a[0][1] * a[1][2] - a[0][2] * a[1][1]) * invDet
            ),
            SIMD3<Float>(
                (a[1][2] * a[2][0] - a[1][0] * a[2][2]) * invDet,
                (a[0][0] * a[2][2] - a[0][2] * a[2][0]) * invDet,
                (a[0][2] * a[1][0] - a[0][0] * a[1][2]) * invDet
            ),
            SIMD3<Float>(
                (a[1][0] * a[2][1] - a[1][1] * a[2][0]) * invDet,
                (a[0][1] * a[2][0] - a[0][0] * a[2][1]) * invDet,
                (a[0][0] * a[1][1] - a[0][1] * a[1][0]) * invDet
            )
        )
        
        return invA * b
    }
}

public struct ProcessedMesh {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
    public let quality: MeshQuality
}

public enum MeshQuality {
    case poor
    case acceptable
    case good
    case excellent
    
    var isAcceptable: Bool {
        self != .poor
    }
}

public enum ProcessingError: Error {
    case bufferCreationFailed
    case commandEncodingFailed
    case processingFailed
    case insufficientMemory(available: UInt64)
}
