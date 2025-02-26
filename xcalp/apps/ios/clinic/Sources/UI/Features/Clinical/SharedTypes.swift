import Foundation
import simd

public struct ProcessedData {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let triangles: [UInt32]
}

public protocol DataProcessor {
    func processData() async throws -> ProcessedData
}

public struct SharedData {
    public let timestamp: Date
    public let data: ProcessedData
    public let quality: QualityMetrics
    
    public init(timestamp: Date, data: ProcessedData, quality: QualityMetrics) {
        self.timestamp = timestamp
        self.data = data
        self.quality = quality
    }
}

public enum ProcessingError: Error {
    case invalidData
    case processingTimeout
    case insufficientQuality
}

extension ProcessedData {
    public func calculateNormals() async -> [SIMD3<Float>] {
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
