import Foundation
import simd

enum MeshValidation {
    static func validateMeshIntegrity(_ mesh: MeshData) throws {
        // Check array lengths match
        guard mesh.vertices.count == mesh.normals.count,
              mesh.vertices.count == mesh.confidence.count else {
            throw ValidationError.arrayLengthMismatch
        }
        
        // Check index bounds
        guard mesh.indices.allSatisfy({ $0 < mesh.vertices.count }) else {
            throw ValidationError.invalidIndices
        }
        
        // Check triangle winding order and validate normals
        try validateTriangles(mesh)
        
        // Check for degenerate triangles
        try validateDegenerateTriangles(mesh)
        
        // Validate confidence values
        guard mesh.confidence.allSatisfy({ $0 >= 0 && $0 <= 1 }) else {
            throw ValidationError.invalidConfidence
        }
        
        // Validate vertex positions
        guard !mesh.vertices.contains(where: { $0.contains(.infinity) || $0.contains(.nan) }) else {
            throw ValidationError.invalidVertexPositions
        }
        
        // Validate normal vectors
        guard mesh.normals.allSatisfy({ abs(length($0) - 1) < 1e-6 }) else {
            throw ValidationError.unnormalizedNormals
        }
    }
    
    static func validateTopology(_ mesh: MeshData) throws -> TopologyMetrics {
        var edgeCounts: [Edge: Int] = [:]
        var nonManifoldEdges = 0
        var boundaryEdges = 0
        
        // Count edge occurrences
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let edges = [
                Edge(v1: Int(mesh.indices[i]), v2: Int(mesh.indices[i + 1])),
                Edge(v1: Int(mesh.indices[i + 1]), v2: Int(mesh.indices[i + 2])),
                Edge(v1: Int(mesh.indices[i + 2]), v2: Int(mesh.indices[i]))
            ]
            
            for edge in edges {
                edgeCounts[edge, default: 0] += 1
            }
        }
        
        // Analyze edge topology
        for (_, count) in edgeCounts {
            if count == 1 {
                boundaryEdges += 1
            } else if count > 2 {
                nonManifoldEdges += 1
            }
        }
        
        return TopologyMetrics(
            edgeCount: edgeCounts.count,
            boundaryEdges: boundaryEdges,
            nonManifoldEdges: nonManifoldEdges,
            isManifold: nonManifoldEdges == 0,
            isWatertight: boundaryEdges == 0
        )
    }
    
    private static func validateTriangles(_ mesh: MeshData) throws {
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            let normal = normalize(cross(v2 - v1, v3 - v1))
            let meshNormal = mesh.normals[Int(mesh.indices[i])]
            
            // Check if triangle normal aligns with vertex normal
            if dot(normal, meshNormal) < 0 {
                throw ValidationError.inconsistentWinding
            }
        }
    }
    
    private static func validateDegenerateTriangles(_ mesh: MeshData) throws {
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            let area = length(cross(v2 - v1, v3 - v1)) * 0.5
            if area < 1e-6 {
                throw ValidationError.degenerateTriangle
            }
        }
    }
}

struct TopologyMetrics {
    let edgeCount: Int
    let boundaryEdges: Int
    let nonManifoldEdges: Int
    let isManifold: Bool
    let isWatertight: Bool
}

enum ValidationError: Error {
    case arrayLengthMismatch
    case invalidIndices
    case invalidConfidence
    case invalidVertexPositions
    case unnormalizedNormals
    case inconsistentWinding
    case degenerateTriangle
    
    var localizedDescription: String {
        switch self {
        case .arrayLengthMismatch:
            return "Mesh arrays have inconsistent lengths"
        case .invalidIndices:
            return "Mesh contains out-of-bounds indices"
        case .invalidConfidence:
            return "Confidence values must be in range [0,1]"
        case .invalidVertexPositions:
            return "Mesh contains invalid vertex positions"
        case .unnormalizedNormals:
            return "Mesh contains unnormalized normal vectors"
        case .inconsistentWinding:
            return "Inconsistent triangle winding order"
        case .degenerateTriangle:
            return "Mesh contains degenerate triangles"
        }
    }
}