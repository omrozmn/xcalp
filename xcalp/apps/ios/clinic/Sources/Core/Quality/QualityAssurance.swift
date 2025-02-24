import ARKit
import Foundation

final class QualityAssurance {
    private let qualityHistory = RollingBuffer<QualitySnapshot>(capacity: 30)
    private let minStableFrames = 10
    private let stabilityThreshold: Float = 0.1
    
    func shouldUseFusion(
        lidarConfidence: Float,
        photogrammetryConfidence: Float
    ) -> Bool {
        // Record current quality metrics
        let snapshot = QualitySnapshot(
            timestamp: Date(),
            lidarConfidence: lidarConfidence,
            photoConfidence: photogrammetryConfidence
        )
        qualityHistory.append(snapshot)
        
        // Check if we have enough history
        guard qualityHistory.count >= minStableFrames else {
            return false
        }
        
        // Check stability of both data sources
        let lidarStable = checkStability { $0.lidarConfidence }
        let photoStable = checkStability { $0.photoConfidence }
        
        guard lidarStable && photoStable else {
            return false
        }
        
        // Calculate complementary scores
        let lidarStrengths = analyzeLidarStrengths()
        let photoStrengths = analyzePhotogrammetryStrengths()
        
        // Determine if fusion would be beneficial
        return shouldFuse(
            lidarStrengths: lidarStrengths,
            photoStrengths: photoStrengths,
            lidarConfidence: lidarConfidence,
            photoConfidence: photogrammetryConfidence
        )
    }
    
    func validateScanQuality(_ frame: ARFrame) -> ScanQualityAssessment {
        let lighting = assessLightingQuality(frame)
        let tracking = assessTrackingQuality(frame)
        let depth = assessDepthQuality(frame)
        let coverage = assessCoverageQuality(frame)
        
        let overallQuality = calculateOverallQuality([
            (lighting, 0.3),
            (tracking, 0.3),
            (depth, 0.2),
            (coverage, 0.2)
        ])
        
        return ScanQualityAssessment(
            overallQuality: overallQuality,
            lighting: lighting,
            tracking: tracking,
            depth: depth,
            coverage: coverage,
            recommendations: generateRecommendations(
                lighting: lighting,
                tracking: tracking,
                depth: depth,
                coverage: coverage
            )
        )
    }
    
    private func checkStability<T: FloatingPoint>(_ valueSelector: (QualitySnapshot) -> T) -> Bool {
        let values = qualityHistory.map(valueSelector)
        let average = values.reduce(0, +) / T(values.count)
        let maxDeviation = values.map { abs($0 - average) }.max() ?? 0
        
        return maxDeviation < T(stabilityThreshold)
    }
    
    private func analyzeLidarStrengths() -> LidarStrengths {
        let recentSnapshots = Array(qualityHistory.suffix(5))
        
        return LidarStrengths(
            depthAccuracy: calculateAverageConfidence(recentSnapshots.map { $0.lidarConfidence }),
            geometricStability: assessGeometricStability(recentSnapshots),
            coverageCompleteness: assessCoverageCompleteness(recentSnapshots)
        )
    }
    
    private func analyzePhotogrammetryStrengths() -> PhotogrammetryStrengths {
        let recentSnapshots = Array(qualityHistory.suffix(5))
        
        return PhotogrammetryStrengths(
            featureQuality: calculateAverageConfidence(recentSnapshots.map { $0.photoConfidence }),
            textureRichness: assessTextureQuality(recentSnapshots),
            detailPreservation: assessDetailPreservation(recentSnapshots)
        )
    }
    
    private func shouldFuse(
        lidarStrengths: LidarStrengths,
        photoStrengths: PhotogrammetryStrengths,
        lidarConfidence: Float,
        photoConfidence: Float
    ) -> Bool {
        // Calculate complementary scores
        let complementaryScore = calculateComplementaryScore(
            lidarStrengths: lidarStrengths,
            photoStrengths: photoStrengths
        )
        
        // Check confidence thresholds
        let meetsConfidenceThresholds = lidarConfidence >= ClinicalConstants.lidarConfidenceThreshold &&
                                      photoConfidence >= ClinicalConstants.minimumPhotogrammetryConfidence
        
        // Check if fusion would be beneficial
        let fusionBeneficial = complementaryScore > 0.7 && // High complementary value
                              meetsConfidenceThresholds
        
        return fusionBeneficial
    }
    
    private func calculateComplementaryScore(
        lidarStrengths: LidarStrengths,
        photoStrengths: PhotogrammetryStrengths
    ) -> Float {
        // Calculate how well the strengths complement each other
        let geometricScore = lidarStrengths.geometricStability
        let textureScore = photoStrengths.textureRichness
        let detailScore = max(
            lidarStrengths.depthAccuracy,
            photoStrengths.detailPreservation
        )
        
        return (geometricScore + textureScore + detailScore) / 3.0
    }
    
    private func assessLightingQuality(_ frame: ARFrame) -> Float {
        guard let lightEstimate = frame.lightEstimate else {
            return 0.0
        }
        
        // Normalize ambient intensity to 0-1 range
        // Optimal range is typically 500-1500 lux
        let normalizedIntensity = Float(lightEstimate.ambientIntensity) / 1500.0
        return min(max(normalizedIntensity, 0.0), 1.0)
    }
    
    private func assessTrackingQuality(_ frame: ARFrame) -> Float {
        switch frame.camera.trackingState {
        case .normal:
            return 1.0
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return 0.3
            case .insufficientFeatures:
                return 0.5
            case .initializing:
                return 0.1
            @unknown default:
                return 0.0
            }
        case .notAvailable:
            return 0.0
        @unknown default:
            return 0.0
        }
    }
    
    private func assessDepthQuality(_ frame: ARFrame) -> Float {
        guard let depthMap = frame.sceneDepth?.depthMap else {
            return 0.0
        }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalPixels = width * height
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 0.0
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        var validDepthPixels = 0
        
        // Sample depth values
        for y in 0..<height {
            for x in 0..<width {
                let pixel = baseAddress.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.size)
                let depth = pixel.assumingMemoryBound(to: Float32.self).pointee
                if depth > 0 {
                    validDepthPixels += 1
                }
            }
        }
        
        return Float(validDepthPixels) / Float(totalPixels)
    }
    
    private func assessCoverageQuality(_ frame: ARFrame) -> Float {
        guard let meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor }) else {
            return 0.0
        }
        
        var totalArea: Float = 0
        var coveredArea: Float = 0
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            
            for i in stride(from: 0, to: faces.count, by: 3) {
                let v1 = vertices[Int(faces[i])]
                let v2 = vertices[Int(faces[i + 1])]
                let v3 = vertices[Int(faces[i + 2])]
                
                let area = triangleArea(v1: v1, v2: v2, v3: v3)
                totalArea += area
                
                if geometry.hasValidTexture(forFaceIndex: i) {
                    coveredArea += area
                }
            }
        }
        
        return totalArea > 0 ? coveredArea / totalArea : 0.0
    }
    
    private func triangleArea(v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>) -> Float {
        let cross = cross(v2 - v1, v3 - v1)
        return length(cross) / 2
    }
    
    private func calculateAverageConfidence(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0, +) / Float(values.count)
    }
    
    private func assessGeometricStability(_ snapshots: [QualitySnapshot]) -> Float {
        // Calculate variance in LiDAR confidence over time
        let confidences = snapshots.map { $0.lidarConfidence }
        let average = calculateAverageConfidence(confidences)
        let variance = confidences.map { pow($0 - average, 2) }.reduce(0, +) / Float(confidences.count)
        
        // Higher stability = lower variance
        return 1.0 - sqrt(variance)
    }
    
    private func assessTextureQuality(_ snapshots: [QualitySnapshot]) -> Float {
        // Average photogrammetry confidence as proxy for texture quality
        calculateAverageConfidence(snapshots.map { $0.photoConfidence })
    }
    
    private func assessDetailPreservation(_ snapshots: [QualitySnapshot]) -> Float {
        // Use recent history to evaluate detail preservation
        let confidences = snapshots.map { $0.photoConfidence }
        return confidences.min() ?? 0.0 // Conservative estimate
    }
    
    private func assessCoverageCompleteness(_ snapshots: [QualitySnapshot]) -> Float {
        // Use LiDAR confidence as proxy for coverage
        calculateAverageConfidence(snapshots.map { $0.lidarConfidence })
    }
    
    private func generateRecommendations(
        lighting: Float,
        tracking: Float,
        depth: Float,
        coverage: Float
    ) -> [ScanningRecommendation] {
        var recommendations: [ScanningRecommendation] = []
        
        if lighting < 0.3 {
            recommendations.append(.improveLighting)
        }
        
        if tracking < 0.5 {
            recommendations.append(.stabilizeDevice)
        }
        
        if depth < 0.7 {
            recommendations.append(.adjustDistance)
        }
        
        if coverage < 0.8 {
            recommendations.append(.increaseCoverage)
        }
        
        return recommendations
    }
    
    private func calculateOverallQuality(_ components: [(value: Float, weight: Float)]) -> Float {
        let totalWeight = components.map { $0.weight }.reduce(0, +)
        let weightedSum = components.map { $0.value * $0.weight }.reduce(0, +)
        return weightedSum / totalWeight
    }
}

// Supporting types
private struct QualitySnapshot {
    let timestamp: Date
    let lidarConfidence: Float
    let photoConfidence: Float
}

private struct LidarStrengths {
    let depthAccuracy: Float
    let geometricStability: Float
    let coverageCompleteness: Float
}

private struct PhotogrammetryStrengths {
    let featureQuality: Float
    let textureRichness: Float
    let detailPreservation: Float
}

struct ScanQualityAssessment {
    let overallQuality: Float
    let lighting: Float
    let tracking: Float
    let depth: Float
    let coverage: Float
    let recommendations: [ScanningRecommendation]
}

enum ScanningRecommendation {
    case improveLighting
    case stabilizeDevice
    case adjustDistance
    case increaseCoverage
    
    var description: String {
        switch self {
        case .improveLighting:
            return "Move to a better lit area"
        case .stabilizeDevice:
            return "Hold the device more steady"
        case .adjustDistance:
            return "Adjust scanning distance"
        case .increaseCoverage:
            return "Scan more areas to increase coverage"
        }
    }
}

// Circular buffer for maintaining history
private class RollingBuffer<T> {
    private var buffer: [T]
    private var currentIndex = 0
    let capacity: Int
    
    var count: Int {
        Swift.min(currentIndex, capacity)
    }
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        buffer.reserveCapacity(capacity)
    }
    
    func append(_ element: T) {
        if buffer.count < capacity {
            buffer.append(element)
        } else {
            buffer[currentIndex % capacity] = element
        }
        currentIndex += 1
    }
    
    func suffix(_ count: Int) -> ArraySlice<T> {
        let actualCount = Swift.min(count, self.count)
        let startIndex = buffer.count - actualCount
        return buffer[startIndex...]
    }
}
