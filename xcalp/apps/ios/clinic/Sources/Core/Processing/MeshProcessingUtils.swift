import Foundation
import simd
import Metal

enum MeshProcessingUtils {
    // MARK: - Geometry Calculations
    
    static func calculateNormal(for vertices: [SIMD3<Float>], using method: NormalCalculationMethod = .robustPCA) -> SIMD3<Float>? {
        guard vertices.count >= 3 else { return nil }
        
        switch method {
        case .robustPCA:
            return calculateRobustPCANormal(vertices)
        case .weightedAverage:
            return calculateWeightedAverageNormal(vertices)
        }
    }
    
    static func decimateMesh(_ mesh: Mesh, targetCount: Int) -> Mesh {
        let vertexCount = mesh.vertices.count
        if vertexCount <= targetCount { return mesh }
        
        // Calculate vertex importance using quadric error metrics
        let importance = calculateVertexImportance(mesh)
        
        // Sort vertices by importance
        let sortedIndices = importance.indices.sorted { importance[$0] > importance[$1] }
        let keepCount = min(targetCount, vertexCount)
        
        // Create new mesh with most important vertices
        let newIndices = Array(sortedIndices.prefix(keepCount))
        let vertexMap = createVertexMap(originalCount: vertexCount, keptIndices: newIndices)
        
        return remapMesh(mesh, using: vertexMap, newCount: keepCount)
    }
    
    // MARK: - Quality Assessment
    
    static func validateMeshTopology(_ mesh: Mesh) -> Bool {
        // Check for non-manifold edges
        let edgeCounts = countEdgeOccurrences(in: mesh)
        let hasNonManifoldEdges = edgeCounts.values.contains { $0 > 2 }
        
        // Check for degenerate triangles
        let hasDegenerateTriangles = checkForDegenerateTriangles(in: mesh)
        
        return !hasNonManifoldEdges && !hasDegenerateTriangles
    }
    
    static func estimatePointCloudNoise(_ points: [SIMD3<Float>], sampleSize: Int = 1000) -> Float {
        let samples = points.count > sampleSize ? Array(points.shuffled().prefix(sampleSize)) : points
        var totalNoise: Float = 0
        var count = 0
        
        for point in samples {
            let neighbors = findNearestNeighbors(point, in: points, k: 10)
            let localNoise = calculateLocalNoise(point, neighbors)
            totalNoise += localNoise
            count += 1
        }
        
        return count > 0 ? totalNoise / Float(count) : 0
    }
    
    // MARK: - Private Methods
    
    private static func calculateRobustPCANormal(_ vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        let centroid = vertices.reduce(.zero, +) / Float(vertices.count)
        var covarianceMatrix = matrix_float3x3()
        
        for vertex in vertices {
            let diff = vertex - centroid
            covarianceMatrix += matrix_float3x3(
                SIMD3(diff.x * diff.x, diff.x * diff.y, diff.x * diff.z),
                SIMD3(diff.y * diff.x, diff.y * diff.y, diff.y * diff.z),
                SIMD3(diff.z * diff.x, diff.z * diff.y, diff.z * diff.z)
            )
        }
        
        covarianceMatrix /= Float(vertices.count)
        
        // Find eigenvector with smallest eigenvalue using power iteration
        return findSmallestEigenvector(covarianceMatrix)
    }
    
    private static func calculateWeightedAverageNormal(_ vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        guard vertices.count >= 3 else { return .zero }
        
        var normal = SIMD3<Float>.zero
        let center = vertices[0]
        
        for i in 1..<(vertices.count - 1) {
            let v1 = vertices[i] - center
            let v2 = vertices[i + 1] - center
            normal += cross(v1, v2)
        }
        
        return normalize(normal)
    }
    
    private static func findSmallestEigenvector(_ matrix: matrix_float3x3) -> SIMD3<Float> {
        var vector = SIMD3<Float>(1, 1, 1)
        let iterations = 8
        
        for _ in 0..<iterations {
            let newVector = matrix * vector
            vector = normalize(newVector)
        }
        
        return vector
    }
    
    private static func calculateVertexImportance(_ mesh: Mesh) -> [Float] {
        var importance = Array(repeating: 0.0 as Float, count: mesh.vertices.count)
        
        // Calculate curvature and feature metrics
        for (i, vertex) in mesh.vertices.enumerated() {
            let neighbors = findVertexNeighbors(i, in: mesh)
            let curvature = calculateLocalCurvature(vertex, neighbors: neighbors.map { mesh.vertices[$0] })
            let featureScore = calculateFeatureScore(vertex, normal: mesh.normals[i], mesh: mesh)
            importance[i] = curvature * 0.7 + featureScore * 0.3
        }
        
        return importance
    }
    
    private static func findVertexNeighbors(_ index: Int, in mesh: Mesh) -> [Int] {
        var neighbors = Set<Int>()
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            for j in 0..<3 {
                if mesh.indices[i + j] == index {
                    neighbors.insert(Int(mesh.indices[i + (j + 1) % 3]))
                    neighbors.insert(Int(mesh.indices[i + (j + 2) % 3]))
                }
            }
        }
        
        return Array(neighbors)
    }
    
    private static func calculateLocalCurvature(_ vertex: SIMD3<Float>, neighbors: [SIMD3<Float>]) -> Float {
        guard !neighbors.isEmpty else { return 0 }
        
        let mean = neighbors.reduce(.zero, +) / Float(neighbors.count)
        let diff = vertex - mean
        return length(diff) / length(mean)
    }
    
    private static func calculateFeatureScore(_ vertex: SIMD3<Float>, normal: SIMD3<Float>, mesh: Mesh) -> Float {
        let neighbors = findVertexNeighbors(mesh.vertices.firstIndex(of: vertex) ?? 0, in: mesh)
        var score: Float = 0
        
        for neighborIndex in neighbors {
            let normalDiff = 1 - abs(dot(normal, mesh.normals[neighborIndex]))
            score += normalDiff
        }
        
        return neighbors.isEmpty ? 0 : score / Float(neighbors.count)
    }
    
    private static func findNearestNeighbors(_ point: SIMD3<Float>, in points: [SIMD3<Float>], k: Int) -> [SIMD3<Float>] {
        var neighbors = points
            .map { ($0, length($0 - point)) }
            .sorted { $0.1 < $1.1 }
            .prefix(k + 1) // +1 because the point itself will be included
            .dropFirst() // Remove the point itself
            .map { $0.0 }
        
        return Array(neighbors)
    }
    
    private static func calculateLocalNoise(_ point: SIMD3<Float>, _ neighbors: [SIMD3<Float>]) -> Float {
        guard !neighbors.isEmpty else { return 0 }
        
        let mean = neighbors.reduce(.zero, +) / Float(neighbors.count)
        return length(point - mean)
    }
}

// MARK: - Supporting Types

enum NormalCalculationMethod {
    case robustPCA
    case weightedAverage
}

private extension Mesh {
    func countEdgeOccurrences() -> [Edge: Int] {
        var edgeCounts: [Edge: Int] = [:]
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let edges = [
                Edge(start: indices[i], end: indices[i + 1]),
                Edge(start: indices[i + 1], end: indices[i + 2]),
                Edge(start: indices[i + 2], end: indices[i])
            ]
            
            for edge in edges {
                edgeCounts[edge, default: 0] += 1
            }
        }
        
        return edgeCounts
    }
}

private struct Edge: Hashable {
    let start: UInt32
    let end: UInt32
    
    init(start: UInt32, end: UInt32) {
        // Store vertices in consistent order
        if start < end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }
}