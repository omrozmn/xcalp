import Foundation
import simd

extension PointCloud {
    /// Calculate the memory footprint of the point cloud in bytes
    var memoryFootprint: Int {
        // Each SIMD3<Float> point is 12 bytes (3 * 4 bytes)
        let pointsSize = points.count * MemoryLayout<SIMD3<Float>>.size
        
        // Add overhead for metadata and optional attributes
        let normalSize = normals?.count ?? 0 * MemoryLayout<SIMD3<Float>>.size
        let confidenceSize = confidence?.count ?? 0 * MemoryLayout<Float>.size
        
        return pointsSize + normalSize + confidenceSize
    }
    
    /// Returns true if the point cloud can fit in the available memory
    func canFitInMemory(limit: Int) -> Bool {
        return memoryFootprint <= limit
    }
    
    /// Creates a downsampled version of the point cloud to fit within memory constraints
    func downsample(toFit memoryLimit: Int) -> PointCloud {
        guard memoryFootprint > memoryLimit else { return self }
        
        let targetCount = (memoryLimit / MemoryLayout<SIMD3<Float>>.size) - 100 // Leave some buffer
        let stride = max(points.count / targetCount, 1)
        
        let downsampledPoints = stride(from: 0, to: points.count, by: stride).map { points[$0] }
        
        // Downsample associated attributes if they exist
        let downsampledNormals = normals.map { normals in
            stride(from: 0, to: normals.count, by: stride).map { normals[$0] }
        }
        
        let downsampledConfidence = confidence.map { confidence in
            stride(from: 0, to: confidence.count, by: stride).map { confidence[$0] }
        }
        
        return PointCloud(
            points: downsampledPoints,
            normals: downsampledNormals,
            confidence: downsampledConfidence
        )
    }
}