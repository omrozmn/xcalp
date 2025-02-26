import Foundation
import simd

public struct QualityMetrics {
    public let overallQuality: Quality
    public let coverage: Float
    public let resolution: Float
    public let confidence: Float
    
    public enum Quality {
        case poor
        case acceptable
        case good
    }
}

public struct GeometryReport {
    public let vertexCount: Int
    public let triangleCount: Int
    public let manifold: Bool
    public let watertight: Bool
}

public struct Hole {
    public let vertices: [SIMD3<Float>]
    public let area: Float
    public let perimeter: Float
}

public enum ValidationError: Error {
    case insufficientCoverage
    case lowResolution
    case nonManifoldGeometry
    case watertightnessViolation
    case excessiveNoise
}

public enum ScanRecommendation {
    case increaseScanResolution
    case improveScaleCoverage
    case fillHoles
    case reduceScanNoise
    case correctOrientation
}
