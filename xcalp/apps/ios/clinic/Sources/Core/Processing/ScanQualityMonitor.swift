import Foundation
import simd
import os.log

final class ScanQualityMonitor {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "scan-quality")
    private var qualityHistory: [Float] = []
    private let maxHistorySize = 30
    private let qualityThreshold: Float = 0.7
    
    func assessScanQuality(_ mesh: Mesh) -> Float {
        let coverage = calculateCoverage(mesh)
        let consistency = calculateConsistency(mesh)
        let density = calculateDensity(mesh)
        
        let quality = (coverage + consistency + density) / 3.0
        updateQualityHistory(quality)
        
        logger.debug("Scan quality assessment: coverage=\(coverage), consistency=\(consistency), density=\(density), overall=\(quality)")
        
        return quality
    }
    
    func isQualitySufficient() -> Bool {
        guard !qualityHistory.isEmpty else { return false }
        return getAverageQuality() >= qualityThreshold
    }
    
    func getTrendAnalysis() -> QualityTrend {
        guard qualityHistory.count >= 2 else { return .stable }
        
        let recent = Array(qualityHistory.suffix(5))
        let trend = calculateTrend(recent)
        
        if trend > 0.1 {
            return .improving
        } else if trend < -0.1 {
            return .degrading
        }
        return .stable
    }
    
    // MARK: - Private Methods
    
    private func calculateCoverage(_ mesh: Mesh) -> Float {
        // Calculate mesh coverage using surface area analysis
        let totalArea = calculateTotalSurfaceArea(mesh)
        let expectedArea = estimateExpectedSurfaceArea(mesh)
        
        return min(1.0, totalArea / expectedArea)
    }
    
    private func calculateConsistency(_ mesh: Mesh) -> Float {
        var consistency: Float = 0
        let vertices = mesh.vertices
        let normals = mesh.normals
        
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let normal = normals[i]
            
            // Find neighbors
            let neighbors = findNeighbors(vertex, in: vertices, radius: 0.01)
            guard !neighbors.isEmpty else { continue }
            
            // Calculate normal consistency
            let neighborConsistency = neighbors.reduce(0.0) { acc, neighbor in
                let neighborIndex = neighbor.index
                let normalDot = abs(dot(normal, normals[neighborIndex]))
                return acc + normalDot
            }
            
            consistency += neighborConsistency / Float(neighbors.count)
        }
        
        return vertices.isEmpty ? 0 : consistency / Float(vertices.count)
    }
    
    private func calculateDensity(_ mesh: Mesh) -> Float {
        let boundingBox = calculateBoundingBox(mesh.vertices)
        let volume = calculateVolume(boundingBox)
        let density = Float(mesh.vertices.count) / volume
        
        // Normalize density against expected density
        return min(1.0, density / ClinicalConstants.minimumPointDensity)
    }
    
    private func updateQualityHistory(_ quality: Float) {
        qualityHistory.append(quality)
        if qualityHistory.count > maxHistorySize {
            qualityHistory.removeFirst()
        }
    }
    
    private func getAverageQuality() -> Float {
        guard !qualityHistory.isEmpty else { return 0 }
        return qualityHistory.reduce(0, +) / Float(qualityHistory.count)
    }
    
    private func calculateTrend(_ values: [Float]) -> Float {
        let n = Float(values.count)
        var sumX: Float = 0
        var sumY: Float = 0
        var sumXY: Float = 0
        var sumXX: Float = 0
        
        for (i, value) in values.enumerated() {
            let x = Float(i)
            sumX += x
            sumY += value
            sumXY += x * value
            sumXX += x * x
        }
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        return slope
    }
    
    private func findNeighbors(_ point: SIMD3<Float>, in points: [SIMD3<Float>], radius: Float) -> [(index: Int, distance: Float)] {
        var neighbors: [(index: Int, distance: Float)] = []
        
        for (index, otherPoint) in points.enumerated() {
            let distance = length(point - otherPoint)
            if distance < radius && distance > 0 {
                neighbors.append((index: index, distance: distance))
            }
        }
        
        return neighbors
    }
    
    private func calculateBoundingBox(_ points: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = points.first else {
            return (SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 0))
        }
        
        var min = first
        var max = first
        
        for point in points {
            min = simd_min(min, point)
            max = simd_max(max, point)
        }
        
        return (min, max)
    }
    
    private func calculateVolume(_ boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Float {
        let dimensions = boundingBox.max - boundingBox.min
        return dimensions.x * dimensions.y * dimensions.z
    }
    
    private func calculateTotalSurfaceArea(_ mesh: Mesh) -> Float {
        var totalArea: Float = 0
        
        // Calculate area for each triangle in the mesh
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            guard i + 2 < mesh.indices.count else { break }
            
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            totalArea += calculateTriangleArea(v1, v2, v3)
        }
        
        return totalArea
    }
    
    private func estimateExpectedSurfaceArea(_ mesh: Mesh) -> Float {
        // Estimate expected surface area based on bounding box
        let boundingBox = calculateBoundingBox(mesh.vertices)
        let dimensions = boundingBox.max - boundingBox.min
        
        // Simple approximation using bounding box surface area
        return 2 * (dimensions.x * dimensions.y +
                   dimensions.y * dimensions.z +
                   dimensions.x * dimensions.z)
    }
    
    private func calculateTriangleArea(_ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>) -> Float {
        let edge1 = v2 - v1
        let edge2 = v3 - v1
        let crossProduct = cross(edge1, edge2)
        return length(crossProduct) * 0.5
    }
}

enum QualityTrend {
    case improving
    case degrading
    case stable
}