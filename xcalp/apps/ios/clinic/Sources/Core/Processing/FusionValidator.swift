import Foundation
import simd

class FusionValidator {
    private let qualityCalculator = QualityMetricsCalculator()
    private let thresholds = ScanningQualityThresholds.self
    
    func validateFusion(lidarPoints: [SIMD3<Float>], photoPoints: [SIMD3<Float>], boundingBox: BoundingBox) -> FusionValidationResult {
        let lidarQuality = validateLidarData(points: lidarPoints, boundingBox: boundingBox)
        let photoQuality = validatePhotogrammetryData(points: photoPoints, boundingBox: boundingBox)
        
        // Check if fusion is possible and beneficial
        let fusionPossible = checkFusionPossibility(
            lidarQuality: lidarQuality,
            photoQuality: photoQuality,
            lidarPoints: lidarPoints,
            photoPoints: photoPoints
        )
        
        // Determine optimal scanning strategy
        let strategy = determineScanningStrategy(
            fusionPossible: fusionPossible,
            lidarQuality: lidarQuality,
            photoQuality: photoQuality
        )
        
        return FusionValidationResult(
            fusionPossible: fusionPossible,
            recommendedStrategy: strategy,
            lidarQuality: lidarQuality,
            photoQuality: photoQuality
        )
    }
    
    private func validateLidarData(points: [SIMD3<Float>], boundingBox: BoundingBox) -> DataQualityMetrics {
        let density = qualityCalculator.calculatePointCloudDensity(points: points, boundingVolume: boundingBox)
        
        let sufficientPoints = points.count >= thresholds.minimumLidarPoints
        let sufficientDensity = density >= 0.7 // 70% of optimal density
        
        return DataQualityMetrics(
            isValid: sufficientPoints && sufficientDensity,
            confidence: density,
            pointCount: points.count
        )
    }
    
    private func validatePhotogrammetryData(points: [SIMD3<Float>], boundingBox: BoundingBox) -> DataQualityMetrics {
        let density = qualityCalculator.calculatePointCloudDensity(points: points, boundingVolume: boundingBox)
        
        let sufficientPoints = points.count >= thresholds.minimumPhotogrammetryPoints
        let sufficientDensity = density >= 0.6 // 60% of optimal density
        
        return DataQualityMetrics(
            isValid: sufficientPoints && sufficientDensity,
            confidence: density,
            pointCount: points.count
        )
    }
    
    private func checkFusionPossibility(
        lidarQuality: DataQualityMetrics,
        photoQuality: DataQualityMetrics,
        lidarPoints: [SIMD3<Float>],
        photoPoints: [SIMD3<Float>]
    ) -> Bool {
        // Check data overlap
        let overlapPercentage = calculateDataOverlap(lidarPoints: lidarPoints, photoPoints: photoPoints)
        guard overlapPercentage >= thresholds.minimumOverlapPercentage else { return false }
        
        // Check combined confidence
        let combinedConfidence = (lidarQuality.confidence + photoQuality.confidence) / 2.0
        guard combinedConfidence >= thresholds.fusionConfidenceThreshold else { return false }
        
        // Verify geometric consistency
        let geometricConsistency = validateGeometricConsistency(
            lidarPoints: lidarPoints,
            photoPoints: photoPoints
        )
        
        return geometricConsistency >= 0.7 // 70% geometric consistency required
    }
    
    private func calculateDataOverlap(lidarPoints: [SIMD3<Float>], photoPoints: [SIMD3<Float>]) -> Float {
        let kdTree = KDTree(points: lidarPoints)
        var overlappingPoints = 0
        
        for point in photoPoints {
            if let nearest = kdTree.nearest(to: point) {
                let distance = length(point - nearest)
                if distance <= thresholds.maximumFusionDistance {
                    overlappingPoints += 1
                }
            }
        }
        
        return Float(overlappingPoints) / Float(photoPoints.count) * 100.0
    }
    
    private func validateGeometricConsistency(lidarPoints: [SIMD3<Float>], photoPoints: [SIMD3<Float>]) -> Float {
        let icpAlignment = ICPAlignment()
        let (_, error) = icpAlignment.align(source: photoPoints, target: lidarPoints)
        
        // Normalize error to 0-1 range (inverted, where 1 is perfect alignment)
        return 1.0 - min(error / thresholds.maximumFusionDistance, 1.0)
    }
    
    private func determineScanningStrategy(
        fusionPossible: Bool,
        lidarQuality: DataQualityMetrics,
        photoQuality: DataQualityMetrics
    ) -> ScanningStrategy {
        if fusionPossible {
            return .fusion
        }
        
        if lidarQuality.isValid && lidarQuality.confidence > photoQuality.confidence {
            return .lidarOnly
        }
        
        if photoQuality.isValid {
            return .photogrammetryOnly
        }
        
        return .needsRecalibration
    }
}

struct DataQualityMetrics {
    let isValid: Bool
    let confidence: Float
    let pointCount: Int
}

struct FusionValidationResult {
    let fusionPossible: Bool
    let recommendedStrategy: ScanningStrategy
    let lidarQuality: DataQualityMetrics
    let photoQuality: DataQualityMetrics
}

enum ScanningStrategy {
    case fusion
    case lidarOnly
    case photogrammetryOnly
    case needsRecalibration
}
