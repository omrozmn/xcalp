import Foundation
import simd

extension SurfaceData {
    func getRegionArea(_ region: String) -> Float {
        guard let regionData = regions[region] else { return 0 }
        return calculateRegionArea(regionData.boundaryPoints)
    }
    
    func getNaturalGrowthPattern(for region: String) -> NaturalPattern {
        guard let regionData = regions[region] else {
            return NaturalPattern(
                direction: .zero,
                variance: 0.2,
                confidence: 0
            )
        }
        
        return NaturalPattern(
            direction: regionData.growthPattern.direction,
            variance: regionData.growthPattern.variance,
            confidence: regionData.growthPattern.significance
        )
    }
    
    func getAdjacentRegions(_ region: String) -> [String] {
        guard let currentRegion = regions[region] else { return [] }
        
        return regions.filter { entry in
            entry.key != region && regionsAreAdjacent(
                currentRegion.boundaryPoints,
                entry.value.boundaryPoints
            )
        }.map { $0.key }
    }
    
    private func calculateRegionArea(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 2 else { return 0 }
        
        // Project points onto best-fit plane for area calculation
        let (projectedPoints, _) = projectPointsToPlane(points)
        
        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += projectedPoints[i].x * projectedPoints[j].y -
                   projectedPoints[j].x * projectedPoints[i].y
        }
        
        return abs(area) / 2
    }
    
    private func regionsAreAdjacent(
        _ points1: [SIMD3<Float>],
        _ points2: [SIMD3<Float>]
    ) -> Bool {
        // Check if regions share any boundary points within threshold
        let threshold: Float = 0.01
        
        for p1 in points1 {
            for p2 in points2 {
                if distance(p1, p2) < threshold {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func projectPointsToPlane(
        _ points: [SIMD3<Float>]
    ) -> (projected: [SIMD2<Float>], normal: SIMD3<Float>) {
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
        
        // Project points onto plane
        let projected = points.map { point -> SIMD2<Float> in
            let projected = projectToPlane(point - centroid, normal: normal)
            return SIMD2<Float>(projected.x, projected.y)
        }
        
        return (projected, normal)
    }
    
    private func calculatePlaneNormal(_ covariance: matrix_float3x3) -> SIMD3<Float> {
        // Power iteration to find smallest eigenvector
        var normal = normalize(SIMD3<Float>(1, 1, 1))
        
        for _ in 0..<10 {
            let next = covariance * normal
            normal = normalize(next)
        }
        
        return normal
    }
    
    private func projectToPlane(_ point: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float> {
        point - normal * dot(point, normal)
    }
}

struct NaturalPattern {
    let direction: SIMD3<Float>
    let variance: Float
    let confidence: Double
}