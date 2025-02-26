import Foundation
import simd

public class DepthColorProcessor {
    private let minDepth: Float
    private let maxDepth: Float
    private let colorMap: [SIMD4<Float>]
    
    public init(minDepth: Float = 0.0, maxDepth: Float = 5.0) {
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        
        // Create a color gradient from red (near) to blue (far)
        self.colorMap = [
            SIMD4<Float>(1.0, 0.0, 0.0, 1.0),  // Red
            SIMD4<Float>(1.0, 0.5, 0.0, 1.0),  // Orange
            SIMD4<Float>(1.0, 1.0, 0.0, 1.0),  // Yellow
            SIMD4<Float>(0.0, 1.0, 0.0, 1.0),  // Green
            SIMD4<Float>(0.0, 0.0, 1.0, 1.0)   // Blue
        ]
    }
    
    public func colorForDepth(_ depth: Float) -> SIMD4<Float> {
        let normalizedDepth = normalize(depth)
        return interpolateColor(normalizedDepth)
    }
    
    public func processPoints(_ points: [Point3D]) -> [(point: Point3D, color: SIMD4<Float>)] {
        return points.map { point in
            let depth = sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
            return (point, colorForDepth(depth))
        }
    }
    
    private func normalize(_ depth: Float) -> Float {
        return (depth - minDepth) / (maxDepth - minDepth)
    }
    
    private func interpolateColor(_ t: Float) -> SIMD4<Float> {
        let clampedT = max(0, min(1, t))
        let segment = clampedT * Float(colorMap.count - 1)
        let index = Int(floor(segment))
        let fraction = segment - Float(index)
        
        if index >= colorMap.count - 1 {
            return colorMap[colorMap.count - 1]
        }
        
        let color1 = colorMap[index]
        let color2 = colorMap[index + 1]
        
        return mix(color1, color2, t: fraction)
    }
    
    private func mix(_ color1: SIMD4<Float>, _ color2: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        return color1 * (1 - t) + color2 * t
    }
    
    public func updateDepthRange(min: Float, max: Float) {
        guard min < max else { return }
        self.minDepth = min
        self.maxDepth = max
    }
}