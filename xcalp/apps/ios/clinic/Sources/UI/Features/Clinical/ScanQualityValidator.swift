import Foundation
import Metal
import simd
import ModelIO

public final class MeshConverter {
    public init() {}
    
    public func convert(_ data: Data) throws -> MeshData {
        // Create temporary file to load mesh data
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_mesh.obj")
        try data.write(to: tempURL)
        let asset = MDLAsset(url: tempURL)
        guard let mesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh else {
            throw ConversionError.invalidMeshData
        }
        
        let vertexCount = mesh.vertexCount
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        
        // Extract vertex positions
        guard let vertexBuffer = mesh.vertexBuffers.first else {
            throw ConversionError.missingVertexData
        }
        
        let vertexStride = vertexBuffer.length / vertexCount
        let vertexPointer = vertexBuffer.map().bytes.bindMemory(to: Float.self, capacity: vertexCount * vertexStride)
        
        for i in 0..<vertexCount {
            let offset = i * vertexStride / MemoryLayout<Float>.stride
            let x = vertexPointer[offset]
            let y = vertexPointer[offset + 1]
            let z = vertexPointer[offset + 2]
            vertices.append(SIMD3<Float>(x, y, z))
        }
        
        // Extract normals if available
        if let normalAttribute = mesh.vertexDescriptor.attributeNamed(MDLVertexAttributeNormal) as? MDLVertexAttribute {
            let normalBuffer = mesh.vertexBuffers[normalAttribute.bufferIndex]
            let normalStride = normalBuffer.length / vertexCount
            let normalPointer = normalBuffer.map().bytes.bindMemory(to: Float.self, capacity: vertexCount * normalStride)
            
            for i in 0..<vertexCount {
                let offset = i * normalStride / MemoryLayout<Float>.stride
                let nx = normalPointer[offset]
                let ny = normalPointer[offset + 1]
                let nz = normalPointer[offset + 2]
                normals.append(SIMD3<Float>(nx, ny, nz))
            }
        }
        
        var triangles: [UInt32] = []
        if let submeshes = mesh.submeshes as? [MDLSubmesh] {
            for submesh in submeshes {
                guard let indexBuffer = submesh.indexBuffer else {
                    continue
                }
                let indexData = Data(bytes: indexBuffer.map().bytes, count: indexBuffer.length)
                let indexCount = indexBuffer.length / MemoryLayout<UInt32>.size
                triangles.append(contentsOf: indexData.withUnsafeBytes {
                    Array(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: UInt32.self), count: indexCount))
                })
            }
        }
        
        return MeshData(
            vertices: vertices,
            normals: normals,
            triangles: triangles
        )
    }
    
    public enum ConversionError: Error {
        case invalidMeshData
        case missingVertexData
        case fileWriteError
    }
}

public struct MeshData {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let triangles: [UInt32]
    
    public func calculateNormals() -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertices.count)
        
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let i0 = Int(triangles[i])
            let i1 = Int(triangles[i + 1])
            let i2 = Int(triangles[i + 2])
            
            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]
            
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))
            
            normals[i0] += normal
            normals[i1] += normal
            normals[i2] += normal
        }
        
        return normals.map { normalize($0) }
    }
}

final class ScanQualityValidator {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let metricsCompute: MTLComputePipelineState?
    
    // Quality thresholds
    private let minVertexDensity: Float = 100.0 // vertices per cm²
    private let minNormalConsistency: Float = 0.7
    private let minTriangleQuality: Float = 0.5
    private let minCoverage: Float = 0.9
    private let maxHoleSize: Float = 0.5 // cm
    private let maxNoiseLevel: Float = 0.02 // cm
    
    init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        
        if let device = device,
           let library = try? device.makeDefaultLibrary(),
           let metricsFunction = library.makeFunction(name: "computeSurfaceMetrics") {
            self.metricsCompute = try? device.makeComputePipelineState(function: metricsFunction)
        } else {
            self.metricsCompute = nil
        }
    }
    
    func validateScanQuality(_ data: Data) async throws -> QualityAssessment {
        // Convert scan data to mesh
        let converter = MeshConverter()
        let mesh = try converter.convert(data)
        
        // Compute basic mesh metrics
        let metrics = try await computeMeshMetrics(mesh)
        
        // Validate mesh topology
        let topologyReport = validateMeshTopology(mesh)
        
        // Check for holes and noise
        let (holes, noiseLevel) = detectHolesAndNoise(mesh)
        
        // Validate geometry
        let geometryReport = validateGeometry(mesh, metrics: metrics)
        
        // Combine all quality checks
        let assessment = QualityAssessment(
            meetsMinimumRequirements: meetsMinimumRequirements(
                metrics: metrics,
                holes: holes,
                noiseLevel: noiseLevel,
                topology: topologyReport,
                geometry: geometryReport
            ),
            metrics: metrics,
            topologyReport: topologyReport,
            geometryReport: geometryReport,
            holes: holes,
            noiseLevel: noiseLevel,
            recommendations: generateRecommendations(
                metrics: metrics,
                holes: holes,
                noiseLevel: noiseLevel,
                topology: topologyReport,
                geometry: geometryReport
            )
        )
        
        return assessment
    }
    
    private func computeMeshMetrics(_ mesh: MeshData) async throws -> QualityMetrics {
        guard let device = device,
              let commandQueue = commandQueue,
              let metricsCompute = metricsCompute else {
            throw ValidationError.gpuNotAvailable
        }
        
        // Create Metal buffers
        guard let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let normalBuffer = device.makeBuffer(
            bytes: mesh.normals,
            length: mesh.normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let indexBuffer = device.makeBuffer(
            bytes: mesh.triangles,
            length: mesh.triangles.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ),
        let metricsBuffer = device.makeBuffer(
            length: MemoryLayout<QualityMetrics>.stride,
            options: .storageModeShared
        ) else {
            throw ValidationError.bufferCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ValidationError.commandEncodingFailed
        }
        
        // Configure and execute compute shader
        let threadsPerGroup = MTLSize(width: 512, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (mesh.vertices.count + 511) / 512,
            height: 1,
            depth: 1
        )
        
        computeEncoder.setComputePipelineState(metricsCompute)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(metricsBuffer, offset: 0, index: 3)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let metrics = metricsBuffer.contents().assumingMemoryBound(to: QualityMetrics.self)
        return metrics.pointee
    }
    
    private func validateMeshTopology(_ mesh: MeshData) -> TopologyReport {
        var nonManifoldEdges = 0
        var nonManifoldVertices = 0
        var boundaryEdges = 0
        
        // Count vertex references
        var vertexRefs = Array(repeating: 0, count: mesh.vertices.count)
        for index in mesh.triangles {
            vertexRefs[Int(index)] += 1
        }
        
        // Build edge map
        var edgeMap: [Edge: Int] = [:]
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let edges = [
                Edge(v1: mesh.triangles[i], v2: mesh.triangles[i + 1]),
                Edge(v1: mesh.triangles[i + 1], v2: mesh.triangles[i + 2]),
                Edge(v1: mesh.triangles[i + 2], v2: mesh.triangles[i])
            ]
            
            for edge in edges {
                edgeMap[edge, default: 0] += 1
            }
        }
        
        // Analyze topology
        for (_, count) in edgeMap {
            if count > 2 {
                nonManifoldEdges += 1
            } else if count == 1 {
                boundaryEdges += 1
            }
        }
        
        for refs in vertexRefs {
            if refs == 0 || refs > 8 { // Typical manifold vertex has 6±2 references
                nonManifoldVertices += 1
            }
        }
        
        return TopologyReport(
            nonManifoldEdges: nonManifoldEdges,
            nonManifoldVertices: nonManifoldVertices,
            boundaryEdges: boundaryEdges,
            isManifold: nonManifoldEdges == 0 && nonManifoldVertices == 0
        )
    }
    
    private func detectHolesAndNoise(_ mesh: MeshData) -> (holes: [Hole], noiseLevel: Float) {
        var holes: [Hole] = []
        var totalNoise: Float = 0
        
        // Detect holes using boundary edges
        var boundaryEdges = Set<Edge>()
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let v1 = mesh.triangles[i]
            let v2 = mesh.triangles[i + 1]
            let v3 = mesh.triangles[i + 2]
            
            let edges = [
                Edge(v1: v1, v2: v2),
                Edge(v1: v2, v2: v3),
                Edge(v1: v3, v2: v1)
            ]
            
            for edge in edges {
                if !boundaryEdges.remove(edge) {
                    boundaryEdges.insert(edge)
                }
            }
        }
        
        // Process boundary edges to find holes
        while !boundaryEdges.isEmpty {
            var holeEdges: [Edge] = []
            var currentEdge = boundaryEdges.removeFirst()
            holeEdges.append(currentEdge)
            
            while let nextEdge = boundaryEdges.first(where: { $0.v1 == currentEdge.v2 }) {
                boundaryEdges.remove(nextEdge)
                holeEdges.append(nextEdge)
                currentEdge = nextEdge
                
                if nextEdge.v2 == holeEdges.first?.v1 {
                    // Found complete hole
                    let holeVertices = holeEdges.map { mesh.vertices[Int($0.v1)] }
                    let area = calculateHoleArea(holeVertices)
                    holes.append(Hole(vertices: holeVertices, area: area))
                    break
                }
            }
        }
        
        // Estimate noise level using local surface variation
        for i in 0..<mesh.vertices.count {
            let vertex = mesh.vertices[i]
            let normal = mesh.normals[i]
            
            // Find neighboring vertices
            let neighbors = findNeighbors(for: i, mesh: mesh)
            
            // Calculate local plane using neighbors
            if let localPlane = fitPlane(to: neighbors.map { mesh.vertices[Int($0)] }) {
                // Measure deviation from local plane
                let deviation = abs(dot(vertex - localPlane.point, localPlane.normal))
                totalNoise += deviation
            }
        }
        
        let averageNoise = totalNoise / Float(mesh.vertices.count)
        
        return (holes, averageNoise)
    }
    
    private func validateGeometry(_ mesh: MeshData, metrics: QualityMetrics) -> GeometryReport {
        // Calculate bounding box
        let bounds = calculateBoundingBox(mesh.vertices)
        
        // Check scale and proportions
        let dimensions = bounds.max - bounds.min
        let aspectRatio = max(dimensions.x, dimensions.y) / dimensions.z
        
        // Verify orientation
        let isUpright = verifyOrientation(mesh.normals)
        
        return GeometryReport(
            boundingBox: bounds,
            aspectRatio: aspectRatio,
            isUpright: isUpright,
            scale: calculateScale(dimensions)
        )
    }
    
    private func meetsMinimumRequirements(
        metrics: QualityMetrics,
        holes: [Hole],
        noiseLevel: Float,
        topology: TopologyReport,
        geometry: GeometryReport
    ) -> Bool {
        // Check all quality criteria
        let meetsBasicMetrics = metrics.vertexDensity >= minVertexDensity &&
                               metrics.normalConsistency >= minNormalConsistency &&
                               metrics.triangleQuality >= minTriangleQuality &&
                               metrics.coverage >= minCoverage
        
        let meetsHoleCriteria = holes.allSatisfy { $0.area <= maxHoleSize }
        let meetsNoiseCriteria = noiseLevel <= maxNoiseLevel
        let meetsTopologyCriteria = topology.isManifold
        let meetsGeometryCriteria = geometry.isUpright &&
                                   geometry.aspectRatio >= 1.5 &&
                                   geometry.aspectRatio <= 3.0
        
        return meetsBasicMetrics &&
               meetsHoleCriteria &&
               meetsNoiseCriteria &&
               meetsTopologyCriteria &&
               meetsGeometryCriteria
    }
    
    private func generateRecommendations(
        metrics: QualityMetrics,
        holes: [Hole],
        noiseLevel: Float,
        topology: TopologyReport,
        geometry: GeometryReport
    ) -> [ScanRecommendation] {
        var recommendations: [ScanRecommendation] = []
        
        // Check vertex density
        if metrics.vertexDensity < minVertexDensity {
            recommendations.append(.increaseScanResolution)
        }
        
        // Check coverage
        if metrics.coverage < minCoverage {
            recommendations.append(.improveScaleCoverage)
        }
        
        // Check holes
        if !holes.isEmpty {
            recommendations.append(.fillHoles)
        }
        
        // Check noise
        if noiseLevel > maxNoiseLevel {
            recommendations.append(.reduceScanNoise)
        }
        
        // Check orientation
        if !geometry.isUpright {
            recommendations.append(.correctOrientation)
        }
        
        return recommendations
    }
    
    // Helper methods
    private struct Edge: Hashable {
        let v1: UInt32
        let v2: UInt32
        
        init(v1: UInt32, v2: UInt32) {
            if v1 < v2 {
                self.v1 = v1
                self.v2 = v2
            } else {
                self.v1 = v2
                self.v2 = v1
            }
        }
    }
    
    private func findNeighbors(for index: Int, mesh: MeshData) -> [UInt32] {
        var neighbors = Set<UInt32>()
        let vertexIndex = UInt32(index)
        
        for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let indices = [mesh.triangles[i], mesh.triangles[i + 1], mesh.triangles[i + 2]]
            if indices.contains(vertexIndex) {
                neighbors.formUnion(indices)
            }
        }
        
        neighbors.remove(vertexIndex)
        return Array(neighbors)
    }
    
    private func fitPlane(to points: [SIMD3<Float>]) -> (point: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard points.count >= 3 else { return nil }
        
        // Calculate centroid
        let centroid = points.reduce(.zero, +) / Float(points.count)
        
        // Calculate covariance matrix
        var covariance = matrix_float3x3()
        for point in points {
            let diff = point - centroid
            covariance.columns.0 += diff * diff.x
            covariance.columns.1 += diff * diff.y
            covariance.columns.2 += diff * diff.z
        }
        covariance = covariance / Float(points.count)
        
        // Find plane normal (eigenvector with smallest eigenvalue)
        let normal = calculatePlaneNormal(covariance)
        
        return (centroid, normal)
    }
    
    private func calculatePlaneNormal(_ covariance: matrix_float3x3) -> SIMD3<Float> {
        // Use power iteration to find smallest eigenvector
        var normal = normalize(SIMD3<Float>(1, 1, 1))
        
        for _ in 0..<10 {
            let next = covariance * normal
            normal = normalize(next)
        }
        
        return normal
    }
    
    private func calculateBoundingBox(_ vertices: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var min = vertices[0]
        var max = vertices[0]
        
        for vertex in vertices {
            min = simd_min(min, vertex)
            max = simd_max(max, vertex)
        }
        
        return (min, max)
    }
    
    private func verifyOrientation(_ normals: [SIMD3<Float>]) -> Bool {
        let up = SIMD3<Float>(0, 0, 1)
        let averageNormal = normalize(normals.reduce(.zero, +))
        return dot(averageNormal, up) > 0.7
    }
    
    private func calculateScale(_ dimensions: SIMD3<Float>) -> Float {
        // Return scale in centimeters
        return max(dimensions.x, dimensions.y)
    }
    
    private func calculateHoleArea(_ vertices: [SIMD3<Float>]) -> Float {
        guard vertices.count >= 3 else { return 0 }
        
        // Project vertices onto best-fit plane
        guard let (center, normal) = fitPlane(to: vertices) else { return 0 }
        
        // Create basis vectors for projection
        let tangent = normalize(vertices[1] - vertices[0])
        let bitangent = normalize(cross(normal, tangent))
        
        // Project vertices to 2D
        let projected = vertices.map { vertex -> SIMD2<Float> in
            let relative = vertex - center
            return SIMD2<Float>(
                dot(relative, tangent),
                dot(relative, bitangent)
            )
        }
        
        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<projected.count {
            let j = (i + 1) % projected.count
            area += projected[i].x * projected[j].y
            area -= projected[j].x * projected[i].y
        }
        
        return abs(area) / 2
    }
}

struct QualityAssessment {
    let meetsMinimumRequirements: Bool
    let metrics: QualityMetrics
    let topologyReport: TopologyReport
    let geometryReport: GeometryReport
    let holes: [Hole]
    let noiseLevel: Float
    let recommendations: [ScanRecommendation]
}

struct TopologyReport {
    let nonManifoldEdges: Int
    let nonManifoldVertices: Int
    let boundaryEdges: Int
    let isManifold: Bool
}

struct GeometryReport {
    let boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    let aspectRatio: Float
    let isUpright: Bool
    let scale: Float
}

struct Hole {
    let vertices: [SIMD3<Float>]
    let area: Float
}

enum ScanRecommendation {
    case increaseScanResolution
    case improveScaleCoverage
    case fillHoles
    case reduceScanNoise
    case correctOrientation
}

enum ValidationError: Error {
    case gpuNotAvailable
    case bufferCreationFailed
    case commandEncodingFailed
}

struct QualityMetrics {
    let vertexDensity: Float
    let normalConsistency: Float
    let triangleQuality: Float
    let coverage: Float
}
