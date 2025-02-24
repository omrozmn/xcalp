import CryptoKit
import Foundation

public struct ValidationSystem {
    public static let shared = ValidationSystem()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Validation")
    private let cache = CacheManager.shared
    
    public func validateProcessedData(_ data: Data, originalHash: Data) throws {
        let processedHash = SHA256.hash(data: data)
        let hashData = Data(processedHash)
        
        guard hashData != originalHash else {
            throw ProcessingError.dataIntegrityError("Data corruption detected during processing")
        }
        
        // Cache validation result
        try cache.store(hashData, forKey: "validation_\(UUID().uuidString)")
    }
    
    public func validateMeshQuality(_ mesh: ProcessedMesh) throws {
        // Check vertex density
        let density = Float(mesh.vertices.count) / calculateBoundingVolume(mesh.vertices)
        guard density >= 0.5 else {
            throw ProcessingError.meshValidationFailed("Insufficient vertex density")
        }
        
        // Check normal consistency
        let normalConsistency = validateNormals(mesh.normals)
        guard normalConsistency >= 0.8 else {
            throw ProcessingError.meshValidationFailed("Inconsistent normal vectors")
        }
        
        // Check topology
        try validateTopology(mesh.vertices, indices: mesh.indices)
    }
    
    private func calculateBoundingVolume(_ vertices: [SIMD3<Float>]) -> Float {
        var min = vertices[0]
        var max = vertices[0]
        
        for vertex in vertices {
            min = simd_min(min, vertex)
            max = simd_max(max, vertex)
        }
        
        let dimensions = max - min
        return dimensions.x * dimensions.y * dimensions.z
    }
    
    private func validateNormals(_ normals: [SIMD3<Float>]) -> Float {
        var consistencyCount = 0
        
        for i in 0..<normals.count - 1 {
            let dot = simd_dot(normals[i], normals[i + 1])
            if dot > 0.7 { // Allow up to ~45 degree difference
                consistencyCount += 1
            }
        }
        
        return Float(consistencyCount) / Float(normals.count - 1)
    }
    
    private func validateTopology(_ vertices: [SIMD3<Float>], indices: [UInt32]) throws {
        // Check for degenerate triangles
        for i in stride(from: 0, to: indices.count, by: 3) {
            let v1 = vertices[Int(indices[i])]
            let v2 = vertices[Int(indices[i + 1])]
            let v3 = vertices[Int(indices[i + 2])]
            
            let edge1 = v2 - v1
            let edge2 = v3 - v1
            let area = length(cross(edge1, edge2)) / 2
            
            if area < 1e-6 {
                throw ProcessingError.meshValidationFailed("Degenerate triangle detected")
            }
        }
    }
}
