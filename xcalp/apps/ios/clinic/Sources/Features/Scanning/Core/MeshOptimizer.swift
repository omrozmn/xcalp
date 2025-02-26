import Foundation
import RealityKit
import simd

public class MeshOptimizer {
    
    private let minPointDistance: Float = 0.005 // 5mm minimum distance between points
    private let normalAngleThreshold: Float = 0.95 // ~18 degrees
    private let outlierThreshold: Float = 3.0 // Standard deviations for outlier removal
    
    public func optimizeMesh(_ points: [Point3D]) -> [Point3D] {
        var optimizedPoints = removeOutliers(points)
        optimizedPoints = removeDuplicates(optimizedPoints)
        optimizedPoints = smoothNormals(optimizedPoints)
        return optimizedPoints
    }
    
    private func removeOutliers(_ points: [Point3D]) -> [Point3D] {
        guard points.count > 3 else { return points }
        
        // Calculate mean and standard deviation of distances
        let distances = calculateDistances(points)
        let mean = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.reduce(0) { $0 + pow($1 - mean, 2) } / Float(distances.count)
        let stdDev = sqrt(variance)
        
        // Filter out points that are too far from neighbors
        return points.enumerated().compactMap { index, point in
            if distances[index] <= mean + outlierThreshold * stdDev {
                return point
            }
            return nil
        }
    }
    
    private func removeDuplicates(_ points: [Point3D]) -> [Point3D] {
        var uniquePoints: [Point3D] = []
        var seen = Set<SIMD3<Float>>()
        
        for point in points {
            let vector = SIMD3<Float>(point.x, point.y, point.z)
            if !seen.contains(vector) {
                seen.insert(vector)
                uniquePoints.append(point)
            }
        }
        
        return uniquePoints
    }
    
    private func smoothNormals(_ points: [Point3D]) -> [Point3D] {
        guard points.count > 3 else { return points }
        
        // Build spatial index for faster neighbor lookups
        let spatialIndex = buildSpatialIndex(points)
        
        return points.map { point in
            let neighbors = findNeighbors(point, in: spatialIndex)
            let smoothedPosition = calculateSmoothedPosition(point, neighbors)
            return Point3D(x: smoothedPosition.x, y: smoothedPosition.y, z: smoothedPosition.z)
        }
    }
    
    private func calculateDistances(_ points: [Point3D]) -> [Float] {
        return points.map { point1 in
            var minDistance = Float.infinity
            for point2 in points where point1 !== point2 {
                let distance = distance(point1, point2)
                minDistance = min(minDistance, distance)
            }
            return minDistance
        }
    }
    
    private func distance(_ p1: Point3D, _ p2: Point3D) -> Float {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        let dz = p1.z - p2.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    
    private func buildSpatialIndex(_ points: [Point3D]) -> [SIMD3<Float>] {
        return points.map { SIMD3<Float>($0.x, $0.y, $0.z) }
    }
    
    private func findNeighbors(_ point: Point3D, in spatialIndex: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let pointVector = SIMD3<Float>(point.x, point.y, point.z)
        return spatialIndex.filter { neighbor in
            let distance = length(neighbor - pointVector)
            return distance > 0 && distance < minPointDistance
        }
    }
    
    private func calculateSmoothedPosition(_ point: Point3D, _ neighbors: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !neighbors.isEmpty else {
            return SIMD3<Float>(point.x, point.y, point.z)
        }
        
        let pointVector = SIMD3<Float>(point.x, point.y, point.z)
        var smoothedPosition = pointVector
        
        for neighbor in neighbors {
            smoothedPosition += neighbor
        }
        
        smoothedPosition /= Float(neighbors.count + 1)
        return smoothedPosition
    }
}