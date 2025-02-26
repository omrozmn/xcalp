import Foundation
import simd
import Metal
import ARKit

final class PointCloudAnalysis {
    // MARK: - Noise Analysis
    
    static func calculateNoiseLevel(_ points: [Point], _ normals: [SIMD3<Float>]) -> Double {
        var totalNoise: Float = 0
        let searchRadius: Float = 0.01 // 1cm radius
        
        for i in 0..<points.count {
            let point = points[i]
            let normal = normals[i]
            
            // Find neighboring points
            let neighbors = findNeighborsInRadius(point.position, points, radius: searchRadius)
            guard !neighbors.isEmpty else { continue }
            
            // Fit local plane using normal
            let projectedDistances = neighbors.map { neighbor -> Float in
                let toNeighbor = neighbor.position - point.position
                return abs(dot(toNeighbor, normal))
            }
            
            // Calculate local noise as standard deviation from fitted plane
            let localNoise = standardDeviation(projectedDistances)
            totalNoise += localNoise
        }
        
        return Double(totalNoise / Float(points.count))
    }
    
    // MARK: - Feature Analysis
    
    static func calculateFeaturePreservation(_ points: [Point], _ normals: [SIMD3<Float>]) -> Double {
        var totalPreservation: Float = 0
        var featureCount = 0
        
        for i in 0..<points.count {
            let point = points[i]
            let normal = normals[i]
            
            // Find feature points using local geometric properties
            if isFeaturePoint(point, normal, points) {
                featureCount += 1
                let preservation = calculateLocalFeaturePreservation(
                    at: point,
                    normal: normal,
                    points: points,
                    normals: normals
                )
                totalPreservation += preservation
            }
        }
        
        return featureCount > 0 ? Double(totalPreservation / Float(featureCount)) : 1.0
    }
    
    // MARK: - Curvature Analysis
    
    static func calculateCurvatureAccuracy(_ points: [Point], _ normals: [SIMD3<Float>]) -> Double {
        var totalAccuracy: Float = 0
        
        for i in 0..<points.count {
            let point = points[i]
            let normal = normals[i]
            
            // Calculate local curvature
            let curvature = estimateLocalCurvature(
                at: point.position,
                normal: normal,
                points: points,
                radius: 0.02 // 2cm radius for curvature estimation
            )
            
            // Compare with expected curvature range
            let accuracy = validateCurvatureAccuracy(curvature)
            totalAccuracy += accuracy
        }
        
        return Double(totalAccuracy / Float(points.count))
    }
    
    // MARK: - Helper Methods
    
    private static func findNeighborsInRadius(_ center: SIMD3<Float>, _ points: [Point], radius: Float) -> [Point] {
        points.filter { point in
            let dist = length(point.position - center)
            return dist > Float.ulpOfOne && dist < radius
        }
    }
    
    private static func isFeaturePoint(_ point: Point, _ normal: SIMD3<Float>, _ points: [Point]) -> Bool {
        let neighbors = findNeighborsInRadius(point.position, points, radius: 0.015)
        guard neighbors.count >= 5 else { return false }
        
        // Calculate normal variation in neighborhood
        let normalVariation = calculateNormalVariation(normal, neighbors)
        
        // High normal variation indicates feature point
        return normalVariation > 0.3
    }
    
    private static func calculateLocalFeaturePreservation(
        at point: Point,
        normal: SIMD3<Float>,
        points: [Point],
        normals: [SIMD3<Float>]
    ) -> Float {
        let neighbors = findNeighborsInRadius(point.position, points, radius: 0.01)
        guard !neighbors.isEmpty else { return 1.0 }
        
        // Calculate geometric consistency
        let consistency = calculateGeometricConsistency(
            point: point.position,
            normal: normal,
            neighbors: neighbors
        )
        
        // Calculate normal stability
        let stability = calculateNormalStability(
            normal: normal,
            neighbors: neighbors,
            points: points,
            normals: normals
        )
        
        return consistency * 0.6 + stability * 0.4
    }
    
    private static func estimateLocalCurvature(
        at point: SIMD3<Float>,
        normal: SIMD3<Float>,
        points: [Point],
        radius: Float
    ) -> Float {
        let neighbors = findNeighborsInRadius(point, points, radius: radius)
        guard !neighbors.isEmpty else { return 0.0 }
        
        // Project neighbors onto tangent plane
        let projectedPoints = neighbors.map { neighbor -> SIMD3<Float> in
            let toNeighbor = neighbor.position - point
            let projected = toNeighbor - dot(toNeighbor, normal) * normal
            return projected
        }
        
        // Fit quadratic surface to projected points
        return fitQuadraticSurface(projectedPoints)
    }
    
    private static func calculateNormalVariation(_ normal: SIMD3<Float>, _ neighbors: [Point]) -> Float {
        let dotProducts = neighbors.map { neighbor in
            abs(dot(normalize(neighbor.position - normal), normal))
        }
        return standardDeviation(dotProducts)
    }
    
    private static func calculateGeometricConsistency(
        point: SIMD3<Float>,
        normal: SIMD3<Float>,
        neighbors: [Point]
    ) -> Float {
        let projectedDistances = neighbors.map { neighbor -> Float in
            let toNeighbor = neighbor.position - point
            return abs(dot(toNeighbor, normal))
        }
        
        let meanDist = projectedDistances.reduce(0, +) / Float(projectedDistances.count)
        return 1.0 / (1.0 + meanDist)
    }
    
    private static func calculateNormalStability(
        normal: SIMD3<Float>,
        neighbors: [Point],
        points: [Point],
        normals: [SIMD3<Float>]
    ) -> Float {
        let neighborNormals = neighbors.compactMap { neighbor -> SIMD3<Float>? in
            guard let idx = points.firstIndex(where: { $0.position == neighbor.position }) else {
                return nil
            }
            return normals[idx]
        }
        
        let dotProducts = neighborNormals.map { neighborNormal in
            abs(dot(normal, neighborNormal))
        }
        
        return dotProducts.reduce(0, +) / Float(dotProducts.count)
    }
    
    private static func fitQuadraticSurface(_ points: [SIMD3<Float>]) -> Float {
        // Simplified quadratic surface fitting
        // Returns approximate curvature
        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let deviations = points.map { length($0 - centroid) }
        return standardDeviation(deviations)
    }
    
    private static func standardDeviation(_ values: [Float]) -> Float {
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Float(values.count))
    }
    
    private static func validateCurvatureAccuracy(_ curvature: Float) -> Float {
        // Compare with anatomically expected curvature ranges
        let maxExpectedCurvature: Float = 0.5 // 50% curvature variation
        return 1.0 - min(curvature / maxExpectedCurvature, 1.0)
    }
}