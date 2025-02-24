import Foundation
import Metal
import MetalKit
import simd

public final class MeshProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Compute pipeline states
    private let normalsPipelineState: MTLComputePipelineState
    private let decimationPipelineState: MTLComputePipelineState
    private let uvPipelineState: MTLComputePipelineState
    private let qualityPipelineState: MTLComputePipelineState
    
    // Performance metrics
    private var processingMetrics: ProcessingMetrics
    
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw ProcessingError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
        
        // Create pipeline states
        do {
            self.normalsPipelineState = try device.makeComputePipelineState(
                function: library.makeFunction(name: "calculateNormals")!
            )
            self.decimationPipelineState = try device.makeComputePipelineState(
                function: library.makeFunction(name: "decimateMesh")!
            )
            self.uvPipelineState = try device.makeComputePipelineState(
                function: library.makeFunction(name: "generatePlanarUVs")!
            )
            self.qualityPipelineState = try device.makeComputePipelineState(
                function: library.makeFunction(name: "analyzeMeshQuality")!
            )
        } catch {
            throw ProcessingError.initializationFailed
        }
        
        self.processingMetrics = ProcessingMetrics()
    }
    
    public func processMesh(_ data: Data) async throws -> ProcessedMesh {
        let perfID = PerformanceMonitor.shared.startMeasuring("meshProcessing")
        let startTime = CACurrentMediaTime()
        
        // Create vertex and index buffers
        let (vertexBuffer, indexBuffer) = try createBuffers(from: data)
        processingMetrics.originalVertexCount = vertexBuffer.length / MemoryLayout<SIMD3<Float>>.stride
        
        // 1. Optimize mesh
        let optimizedMesh = try await optimizeMesh(
            vertices: vertexBuffer,
            indices: indexBuffer
        )
        processingMetrics.optimizedVertexCount = optimizedMesh.vertices.length / MemoryLayout<SIMD3<Float>>.stride
        
        // 2. Calculate normals
        let normalsBuffer = try await calculateNormals(
            for: optimizedMesh
        )
        
        // 3. Generate UV coordinates
        let uvBuffer = try await generateUVCoordinates(
            for: optimizedMesh
        )
        
        // 4. Analyze mesh quality
        let quality = try await analyzeMeshQuality(
            vertices: optimizedMesh.vertices,
            normals: normalsBuffer
        )
        
        processingMetrics.processingTime = CACurrentMediaTime() - startTime
        processingMetrics.memoryUsage = Int64(vertexBuffer.length + indexBuffer.length + normalsBuffer.length + uvBuffer.length)
        
        PerformanceMonitor.shared.endMeasuring("meshProcessing", signpostID: perfID)
        
        return ProcessedMesh(
            vertices: optimizedMesh.vertices,
            indices: optimizedMesh.indices,
            normals: normalsBuffer,
            uvs: uvBuffer,
            quality: quality,
            metrics: processingMetrics
        )
    }
    
    private func optimizeMesh(
        vertices: MTLBuffer,
        indices: MTLBuffer
    ) async throws -> OptimizedMesh {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.processingFailed("Failed to create command buffer")
        }
        
        // Create quadrics buffer
        let quadricsBuffer = device.makeBuffer(
            length: vertices.length,
            options: .storageModePrivate
        )
        
        let removedBuffer = device.makeBuffer(
            length: vertices.length / MemoryLayout<SIMD3<Float>>.stride * MemoryLayout<UInt32>.size,
            options: .storageModePrivate
        )
        
        computeEncoder.setComputePipelineState(decimationPipelineState)
        computeEncoder.setBuffer(vertices, offset: 0, index: 0)
        computeEncoder.setBuffer(indices, offset: 0, index: 1)
        computeEncoder.setBuffer(quadricsBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(removedBuffer, offset: 0, index: 3)
        
        let gridSize = MTLSize(
            width: vertices.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        
        let threadGroupSize = MTLSize(
            width: min(device.maxThreadsPerThreadgroup, gridSize.width),
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // TODO: Collect optimized vertices and rebuild index buffer
        // For now, return original mesh
        return OptimizedMesh(vertices: vertices, indices: indices)
    }
    
    private func calculateNormals(
        for mesh: OptimizedMesh
    ) async throws -> MTLBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.processingFailed("Failed to create command buffer")
        }
        
        let normalsBuffer = device.makeBuffer(
            length: mesh.vertices.length,
            options: .storageModeShared
        )
        
        computeEncoder.setComputePipelineState(normalsPipelineState)
        computeEncoder.setBuffer(mesh.vertices, offset: 0, index: 0)
        computeEncoder.setBuffer(mesh.indices, offset: 0, index: 1)
        computeEncoder.setBuffer(normalsBuffer, offset: 0, index: 2)
        
        let gridSize = MTLSize(
            width: mesh.vertices.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        
        let threadGroupSize = MTLSize(
            width: min(device.maxThreadsPerThreadgroup, gridSize.width),
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return normalsBuffer!
    }
    
    private func generateUVCoordinates(
        for mesh: OptimizedMesh
    ) async throws -> MTLBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.processingFailed("Failed to create command buffer")
        }
        
        let uvBuffer = device.makeBuffer(
            length: mesh.vertices.length / 3 * 2,  // 2 floats per UV coordinate
            options: .storageModeShared
        )
        
        computeEncoder.setComputePipelineState(uvPipelineState)
        computeEncoder.setBuffer(mesh.vertices, offset: 0, index: 0)
        computeEncoder.setBuffer(uvBuffer, offset: 0, index: 1)
        
        let gridSize = MTLSize(
            width: mesh.vertices.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        
        let threadGroupSize = MTLSize(
            width: min(device.maxThreadsPerThreadgroup, gridSize.width),
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return uvBuffer!
    }
    
    private func analyzeMeshQuality(
        vertices: MTLBuffer,
        normals: MTLBuffer
    ) async throws -> MeshQuality {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.processingFailed("Failed to create command buffer")
        }
        
        let qualityBuffer = device.makeBuffer(
            length: vertices.length / MemoryLayout<SIMD3<Float>>.stride * 2 * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        
        computeEncoder.setComputePipelineState(qualityPipelineState)
        computeEncoder.setBuffer(vertices, offset: 0, index: 0)
        computeEncoder.setBuffer(normals, offset: 0, index: 1)
        computeEncoder.setBuffer(qualityBuffer, offset: 0, index: 2)
        
        let gridSize = MTLSize(
            width: vertices.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        
        let threadGroupSize = MTLSize(
            width: min(device.maxThreadsPerThreadgroup, gridSize.width),
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Calculate average quality metrics
        let qualityData = qualityBuffer!.contents().assumingMemoryBound(to: Float.self)
        let count = vertices.length / MemoryLayout<SIMD3<Float>>.stride
        
        var normalConsistency: Float = 0
        var surfaceSmoothness: Float = 0
        
        for i in 0..<count {
            normalConsistency += qualityData[i * 2]
            surfaceSmoothness += qualityData[i * 2 + 1]
        }
        
        normalConsistency /= Float(count)
        surfaceSmoothness /= Float(count)
        
        // TODO: Implement hole detection
        return MeshQuality(
            vertexDensity: Float(count) / 1000.0,  // Vertices per 1000 units³
            surfaceSmoothness: surfaceSmoothness,
            normalConsistency: normalConsistency,
            holes: []  // Placeholder for hole detection
        )
    }
    
    private func createBuffers(from data: Data) throws -> (MTLBuffer, MTLBuffer) {
        // Parse vertex and index data from the raw mesh data
        // Format: [vertices][normals][indices]
        
        let vertexCount = data.count / (3 * MemoryLayout<Float>.size)
        let indexCount = vertexCount / 3  // Assuming triangles
        
        guard let vertexBuffer = device.makeBuffer(
            bytes: data.bytes,
            length: vertexCount * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ) else {
            throw ProcessingError.bufferCreationFailed
        }
        
        guard let indexBuffer = device.makeBuffer(
            bytes: data.bytes.advanced(by: vertexCount * MemoryLayout<SIMD3<Float>>.stride),
            length: indexCount * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw ProcessingError.bufferCreationFailed
        }
        
        return (vertexBuffer, indexBuffer)
    }
}

// MARK: - Supporting Types
extension MeshProcessor {
    public struct ProcessedMesh {
        public let vertices: MTLBuffer
        public let indices: MTLBuffer
        public let normals: MTLBuffer
        public let uvs: MTLBuffer
        public let quality: MeshQuality
        public let metrics: ProcessingMetrics
    }
    
    public struct OptimizedMesh {
        public let vertices: MTLBuffer
        public let indices: MTLBuffer
    }
    
    public struct MeshQuality {
        public let vertexDensity: Float
        public let surfaceSmoothness: Float
        public let normalConsistency: Float
        public let holes: [HoleInfo]
        
        public struct HoleInfo {
            public let center: SIMD3<Float>
            public let radius: Float
        }
    }
    
    public struct ProcessingMetrics {
        public var originalVertexCount: Int = 0
        public var optimizedVertexCount: Int = 0
        public var processingTime: TimeInterval = 0
        public var memoryUsage: Int64 = 0
    }
    
    public enum ProcessingError: Error {
        case initializationFailed
        case bufferCreationFailed
        case processingFailed(String)
        case optimizationFailed
        case qualityCheckFailed
    }
}
