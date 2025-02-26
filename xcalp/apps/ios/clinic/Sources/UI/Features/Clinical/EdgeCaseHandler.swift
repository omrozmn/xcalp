import Foundation
import simd

final class EdgeCaseHandler {
    private let irregularityCutoff: Float = 0.7
    private let minRegionSize: Float = 2.0 // cm²
    private let maxDirectionVariance: Float = 0.4
    
    func handleIrregularPatterns(
        in surfaceData: SurfaceData,
        ethnicity: String? = nil
    ) -> [String: RefinedPattern] {
        var refinedPatterns: [String: RefinedPattern] = [:]
        
        for (region, data) in surfaceData.regions {
            let pattern = data.growthPattern
            
            // Check if this is an edge case needing refinement
            if needsRefinement(pattern: pattern, region: region) {
                let refinedPattern = refinePattern(
                    original: pattern,
                    region: region,
                    normals: data.surfaceNormals,
                    ethnicity: ethnicity
                )
                refinedPatterns[region] = refinedPattern
            }
        }
        
        return refinedPatterns
    }
    
    private func needsRefinement(pattern: GrowthPattern, region: String) -> Bool {
        // Check various conditions that might indicate an edge case
        let hasHighVariance = pattern.variance > maxDirectionVariance
        let hasLowSignificance = pattern.significance < irregularityCutoff
        let isTransitionArea = isRegionalTransition(region)
        
        return hasHighVariance || hasLowSignificance || isTransitionArea
    }
    
    private func refinePattern(
        original: GrowthPattern,
        region: String,
        normals: [SIMD3<Float>],
        ethnicity: String?
    ) -> RefinedPattern {
        // Apply ethnicity-specific adjustments if available
        let adjustedDirection = adjustForEthnicity(
            direction: original.direction,
            region: region,
            ethnicity: ethnicity
        )
        
        // Smooth out variance based on surrounding normals
        let smoothedVariance = calculateSmoothedVariance(
            baseDirection: adjustedDirection,
            normals: normals
        )
        
        // Adjust significance based on pattern coherence
        let adjustedSignificance = recalculateSignificance(
            original: original.significance,
            variance: smoothedVariance,
            region: region
        )
        
        return RefinedPattern(
            direction: adjustedDirection,
            significance: adjustedSignificance,
            variance: smoothedVariance,
            confidence: calculateConfidence(
                originalPattern: original,
                refinedVariance: smoothedVariance
            ),
            needsManualReview: shouldFlagForReview(
                significance: adjustedSignificance,
                variance: smoothedVariance
            )
        )
    }
    
    private func adjustForEthnicity(
        direction: SIMD3<Float>,
        region: String,
        ethnicity: String?
    ) -> SIMD3<Float> {
        guard let ethnicity = ethnicity else { return direction }
        
        // Apply ethnicity-specific angle adjustments
        let adjustment: Float = switch ethnicity.lowercased() {
            case "asian":
                region.contains("temple") ? 15.0 : 10.0
            case "african":
                region.contains("crown") ? 20.0 : 15.0
            case "caucasian":
                region.contains("hairline") ? 12.0 : 8.0
            default:
                0.0
        }
        
        if adjustment == 0 { return direction }
        
        // Convert adjustment to radians and rotate direction
        let angle = adjustment * .pi / 180.0
        let rotationAxis = normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
        return rotateVector(direction, around: rotationAxis, by: angle)
    }
    
    private func calculateSmoothedVariance(
        baseDirection: SIMD3<Float>,
        normals: [SIMD3<Float>]
    ) -> Float {
        let angles = normals.map { normal in
            acos(abs(dot(normalize(normal), normalize(baseDirection))))
        }
        
        // Remove outliers (beyond 2 standard deviations)
        let mean = angles.reduce(0, +) / Float(angles.count)
        let variance = angles.map { pow($0 - mean, 2) }.reduce(0, +) / Float(angles.count)
        let stdDev = sqrt(variance)
        
        let filteredAngles = angles.filter { angle in
            abs(angle - mean) <= 2 * stdDev
        }
        
        return filteredAngles.reduce(0, +) / Float(filteredAngles.count)
    }
    
    private func recalculateSignificance(
        original: Double,
        variance: Float,
        region: String
    ) -> Double {
        var adjusted = original
        
        // Adjust based on variance
        adjusted *= Double(1.0 - variance)
        
        // Regional adjustments
        adjusted *= switch region {
            case let r where r.contains("hairline"): 1.2 // Higher significance for hairline
            case let r where r.contains("crown"): 1.1   // Slightly higher for crown
            case let r where r.contains("temple"): 0.9  // Slightly lower for temples
            default: 1.0
        }
        
        return min(max(adjusted, 0.0), 1.0)
    }
    
    private func calculateConfidence(
        originalPattern: GrowthPattern,
        refinedVariance: Float
    ) -> Double {
        let varianceImprovement = (originalPattern.variance - refinedVariance) / originalPattern.variance
        return min(1.0, originalPattern.significance + Double(varianceImprovement) * 0.3)
    }
    
    private func shouldFlagForReview(
        significance: Double,
        variance: Float
    ) -> Bool {
        significance < 0.6 || variance > maxDirectionVariance * 1.5
    }
    
    private func isRegionalTransition(_ region: String) -> Bool {
        region.contains("transition") || 
        region.contains("border") ||
        region.contains("junction")
    }
    
    private func rotateVector(
        _ vector: SIMD3<Float>,
        around axis: SIMD3<Float>,
        by angle: Float
    ) -> SIMD3<Float> {
        let cosA = cos(angle)
        let sinA = sin(angle)
        
        // Rodrigues rotation formula
        return vector * cosA +
               cross(axis, vector) * sinA +
               axis * dot(axis, vector) * (1 - cosA)
    }
}

struct RefinedPattern {
    let direction: SIMD3<Float>
    let significance: Double
    let variance: Float
    let confidence: Double
    let needsManualReview: Bool
}