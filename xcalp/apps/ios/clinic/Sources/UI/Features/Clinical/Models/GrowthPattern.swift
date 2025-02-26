import Foundation
import simd

public struct GrowthPattern {
    public let direction: SIMD3<Float>
    public let significance: Float
    public let confidence: Float
    
    public init(direction: SIMD3<Float>, significance: Float, confidence: Float) {
        self.direction = direction
        self.significance = significance
        self.confidence = confidence
    }
}

public struct Landmark {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let curvature: Float
}

public struct RegionMask {
    public let vertices: [SIMD3<Float>]
    public let indices: [UInt32]
    public let density: Float
}
