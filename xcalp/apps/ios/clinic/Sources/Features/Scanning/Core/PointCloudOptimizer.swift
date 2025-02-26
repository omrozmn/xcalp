import Foundation
import simd

public class PointCloudOptimizer {
    private let voxelSize: Float
    private let maxPoints: Int
    private let minDistance: Float
    
    public init(voxelSize: Float = 0.01, maxPoints: Int = 100000, minDistance: Float = 0.005) {
        self.voxelSize = voxelSize
        self.maxPoints = maxPoints
        self.minDistance = minDistance
    }
    
    public func optimizePointCloud(_ points: [Point3D]) -> [Point3D] {
        guard !points.isEmpty else { return [] }
        
        // First pass: Voxel-based decimation
        let decimatedPoints = voxelDownsample(points)
        
        // Second pass: Statistical outlier removal
        let cleanedPoints = removeOutliers(decimatedPoints)
        
        // Third pass: Clustering
        return clusterPoints(cleanedPoints)
    }
    
    private func voxelDownsample(_ points: [Point3D]) -> [Point3D] {
        var voxelGrid: [SIMD3<Int>: [Point3D]] = [:]
        
        // Assign points to voxels
        for point in points {
            let voxelCoord = SIMD3<Int>(
                Int(floor(point.x / voxelSize)),
                Int(floor(point.y / voxelSize)),
                Int(floor(point.z / voxelSize))
            )
            voxelGrid[voxelCoord, default: []].append(point)
        }
        
        // Calculate centroid for each voxel
        return voxelGrid.values.map { voxelPoints in
            let sum = voxelPoints.reduce(SIMD3<Float>(0, 0, 0)) { result, point in
                result + SIMD3<Float>(point.x, point.y, point.z)
            }
            let centroid = sum / Float(voxelPoints.count)
            return Point3D(x: centroid.x, y: centroid.y, z: centroid.z)
        }
    }
    
    private func removeOutliers(_ points: [Point3D]) -> [Point3D] {
        guard points.count > 3 else { return points }
        
        // Calculate mean distance to k nearest neighbors
        let k = min(20, points.count - 1)
        var meanDistances: [Float] = []
        
        for point in points {
            let distances = points
                .map { neighborPoint in
                    distance(from: point, to: neighborPoint)
                }
                .sorted()
                .prefix(k + 1) // +1 because the first distance is to itself (0)
                .dropFirst() // Remove the self-distance
            
            let meanDistance = distances.reduce(0, +) / Float(k)
            meanDistances.append(meanDistance)
        }
        
        // Calculate threshold based on standard deviation
        let mean = meanDistances.reduce(0, +) / Float(meanDistances.count)
        let variance = meanDistances.reduce(0) { sum, distance in
            sum + pow(distance - mean, 2)
        } / Float(meanDistances.count)
        let stdDev = sqrt(variance)
        let threshold = mean + 2 * stdDev
        
        // Filter points based on threshold
        return zip(points, meanDistances)
            .filter { $0.1 < threshold }
            .map { $0.0 }
    }
    
    private func clusterPoints(_ points: [Point3D]) -> [Point3D] {
        var clusters: [[Point3D]] = []
        var processedPoints = Set<Point3D>()
        
        for point in points {
            guard !processedPoints.contains(point) else { continue }
            
            var cluster: [Point3D] = [point]
            processedPoints.insert(point)
            
            var searchQueue = [point]
            while let currentPoint = searchQueue.popLast() {
                let neighbors = findNeighbors(of: currentPoint, in: points)
                    .filter { !processedPoints.contains($0) }
                
                for neighbor in neighbors {
                    cluster.append(neighbor)
                    processedPoints.insert(neighbor)
                    searchQueue.append(neighbor)
                }
            }
            
            if cluster.count >= 3 {
                clusters.append(cluster)
            }
        }
        
        // Return centroids of clusters
        return clusters.map { cluster in
            let sum = cluster.reduce(SIMD3<Float>(0, 0, 0)) { result, point in
                result + SIMD3<Float>(point.x, point.y, point.z)
            }
            let centroid = sum / Float(cluster.count)
            return Point3D(x: centroid.x, y: centroid.y, z: centroid.z)
        }
    }
    
    private func findNeighbors(of point: Point3D, in points: [Point3D]) -> [Point3D] {
        return points.filter {
            $0 != point && distance(from: point, to: $0) < minDistance
        }
    }
    
    private func distance(from p1: Point3D, to p2: Point3D) -> Float {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        let dz = p1.z - p2.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}