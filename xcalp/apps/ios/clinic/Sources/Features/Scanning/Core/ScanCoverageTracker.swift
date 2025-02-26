import Foundation
import simd

public class ScanCoverageTracker {
    private let voxelSize: Float
    private var voxelGrid: Set<SIMD3<Int>> = []
    private var boundingBox: BoundingBox?
    private let minCoverage: Float = 0.7
    
    public init(voxelSize: Float = 0.02) { // 2cm voxels
        self.voxelSize = voxelSize
    }
    
    public func updateCoverage(with points: [Point3D]) -> Float {
        // Update bounding box
        updateBoundingBox(points)
        
        // Add points to voxel grid
        for point in points {
            let voxel = pointToVoxel(point)
            voxelGrid.insert(voxel)
        }
        
        return calculateCoverage()
    }
    
    private func updateBoundingBox(_ points: [Point3D]) {
        guard !points.isEmpty else { return }
        
        if boundingBox == nil {
            let firstPoint = SIMD3<Float>(points[0].x, points[0].y, points[0].z)
            boundingBox = BoundingBox(min: firstPoint, max: firstPoint)
        }
        
        for point in points {
            let p = SIMD3<Float>(point.x, point.y, point.z)
            boundingBox?.min = simd_min(boundingBox!.min, p)
            boundingBox?.max = simd_max(boundingBox!.max, p)
        }
    }
    
    private func pointToVoxel(_ point: Point3D) -> SIMD3<Int> {
        return SIMD3<Int>(
            Int(floor(point.x / voxelSize)),
            Int(floor(point.y / voxelSize)),
            Int(floor(point.z / voxelSize))
        )
    }
    
    private func calculateCoverage() -> Float {
        guard let bounds = boundingBox else { return 0 }
        
        // Calculate expected number of voxels based on bounding box
        let dimensions = bounds.max - bounds.min
        let expectedVoxels = Float(
            Int(ceil(dimensions.x / voxelSize)) *
            Int(ceil(dimensions.y / voxelSize)) *
            Int(ceil(dimensions.z / voxelSize))
        )
        
        // Calculate actual coverage
        let coverage = Float(voxelGrid.count) / expectedVoxels
        
        // Normalize coverage to account for empty space
        return min(coverage * 1.5, 1.0)
    }
    
    public func isCoverageComplete() -> Bool {
        return calculateCoverage() >= minCoverage
    }
    
    public func reset() {
        voxelGrid.removeAll()
        boundingBox = nil
    }
    
    public func getCoverageHeatmap() -> [(position: SIMD3<Float>, density: Float)] {
        guard let bounds = boundingBox else { return [] }
        
        var heatmap: [(position: SIMD3<Float>, density: Float)] = []
        var densityMap: [SIMD3<Int>: Int] = [:]
        
        // Calculate density for each voxel
        for voxel in voxelGrid {
            let neighborCount = countNeighbors(for: voxel)
            densityMap[voxel] = neighborCount
        }
        
        // Normalize densities and convert to world space positions
        let maxDensity = Float(densityMap.values.max() ?? 1)
        for (voxel, count) in densityMap {
            let position = SIMD3<Float>(
                Float(voxel.x) * voxelSize,
                Float(voxel.y) * voxelSize,
                Float(voxel.z) * voxelSize
            )
            let density = Float(count) / maxDensity
            heatmap.append((position, density))
        }
        
        return heatmap
    }
    
    private func countNeighbors(for voxel: SIMD3<Int>, radius: Int = 1) -> Int {
        var count = 0
        
        for x in -radius...radius {
            for y in -radius...radius {
                for z in -radius...radius {
                    let neighbor = voxel &+ SIMD3<Int>(x, y, z)
                    if voxelGrid.contains(neighbor) {
                        count += 1
                    }
                }
            }
        }
        
        return count
    }
}