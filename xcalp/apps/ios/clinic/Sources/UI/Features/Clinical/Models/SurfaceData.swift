import Foundation
import simd

public struct SurfaceData {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let curvatureMap: [Float]
    public let regions: [String: RegionData]
    public let metrics: SurfaceMetrics
    
    public struct RegionData {
        public let boundaryPoints: [SIMD3<Float>]
        public let surfaceNormals: [SIMD3<Float>]
        public let growthPattern: GrowthPattern
    }
    
    public struct GrowthPattern {
        public let direction: SIMD3<Float>
        public let significance: Float
    }
    
    public struct SurfaceMetrics {
        public let curvatureMap: [Float]
        public let quality: SurfaceQuality
    }
    
    public struct SurfaceQuality {
        public let normalConsistency: Float
        public let triangleQuality: Float
    }
}

public struct Direction {
    public let angle: Double
    public let region: String
}

public struct NaturalPattern {
    public let direction: SIMD3<Float>
    public let strength: Float
}

public enum PredictionError: Error {
    case invalidOutput
    case processingError
}
