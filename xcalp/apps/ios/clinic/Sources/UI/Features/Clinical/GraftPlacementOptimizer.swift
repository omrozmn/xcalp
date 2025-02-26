import Foundation
import simd

public final class GraftPlacementOptimizer {
    private let maxGraftsPerCm2: Double = 45.0
    private let minGraftsPerCm2: Double = 15.0
    private let naturalVariance: Float = 0.15
    private let blendingDistance: Float = 0.5 // cm
    private let edgeTaperDistance: Float = 0.3 // cm
    
    public func optimizeGraftPlacements(
        surfaceData: SurfaceData,
        densityAnalysis: DensityAnalysis,
        targetDensity: Double,
        preserveExisting: Bool,
        ethnicity: String? = nil
    ) async throws -> GraftPlan {
        // Calculate priorities for each region
        let priorities = calculateRegionPriorities(
            densityAnalysis: densityAnalysis,
            surfaceData: surfaceData
        )
        
        // Calculate total required grafts
        let totalRequiredGrafts = calculateRequiredGrafts(
            densityAnalysis: densityAnalysis,
            targetDensity: targetDensity,
            surfaceData: surfaceData,
            preserveExisting: preserveExisting
        )
        
        // Distribute grafts among regions
        let distribution = distributeGrafts(
            count: totalRequiredGrafts,
            priorities: priorities,
            surfaceData: surfaceData
        )
        
        // Calculate optimal directions for each graft
        let directions = try calculateOptimalDirections(
            distribution: distribution,
            surfaceData: surfaceData,
            ethnicity: ethnicity
        )
        
        return GraftPlan(
            totalGrafts: totalRequiredGrafts,
            regions: distribution,
            directions: directions
        )
    }
    
    private func calculateRegionPriorities(
        densityAnalysis: DensityAnalysis,
        surfaceData: SurfaceData
    ) -> [String: Double] {
        var priorities: [String: Double] = [:]
        let targetDensityVariance = 0.2 // 20% variance threshold
        
        for (region, currentDensity) in densityAnalysis.regionalDensities {
            // Base priority on density deficit
            let densityFactor = 1.0 - (currentDensity / densityAnalysis.averageDensity)
            
            // Adjust for region importance
            let importanceFactor = getRegionImportance(region)
            
            // Adjust for pattern quality
            let patternFactor = surfaceData.regions[region].map {
                Double($0.growthPattern.significance)
            } ?? 1.0
            
            // Calculate final priority
            priorities[region] = max(0,
                densityFactor * importanceFactor * patternFactor
            )
        }
        
        return priorities
    }
    
    private func calculateRequiredGrafts(
        densityAnalysis: DensityAnalysis,
        targetDensity: Double,
        surfaceData: SurfaceData,
        preserveExisting: Bool
    ) -> Int {
        var totalRequired = 0
        
        for (region, currentDensity) in densityAnalysis.regionalDensities {
            let area = Double(surfaceData.getRegionArea(region))
            let targetGrafts = Int(targetDensity * area)
            let existingGrafts = preserveExisting ? Int(currentDensity * area) : 0
            
            totalRequired += max(0, targetGrafts - existingGrafts)
        }
        
        return totalRequired
    }
    
    private func distributeGrafts(
        count: Int,
        priorities: [String: Double],
        surfaceData: SurfaceData
    ) -> [String: Int] {
        var distribution: [String: Int] = [:]
        var remainingGrafts = count
        
        // Sort regions by priority
        let sortedRegions = priorities.sorted { $0.value > $1.value }
        
        // Initial distribution based on priorities
        for (region, priority) in sortedRegions {
            let area = Double(surfaceData.getRegionArea(region))
            let maxForRegion = Int(area * maxGraftsPerCm2)
            let allocation = min(
                remainingGrafts,
                Int(Double(maxForRegion) * priority)
            )
            
            distribution[region] = allocation
            remainingGrafts -= allocation
        }
        
        // Distribute any remaining grafts proportionally
        if remainingGrafts > 0 {
            let totalArea = surfaceData.regions.reduce(0.0) { sum, entry in
                sum + Double(surfaceData.getRegionArea(entry.key))
            }
            
            for region in distribution.keys {
                let areaRatio = Double(surfaceData.getRegionArea(region)) / totalArea
                let additional = Int(Double(remainingGrafts) * areaRatio)
                distribution[region] = (distribution[region] ?? 0) + additional
            }
        }
        
        return distribution
    }
    
    private func calculateOptimalDirections(
        distribution: [String: Int],
        surfaceData: SurfaceData,
        ethnicity: String?
    ) throws -> [Direction] {
        var directions: [Direction] = []
        
        for (region, count) in distribution {
            guard let regionData = surfaceData.regions[region] else { continue }
            
            let naturalPattern = surfaceData.getNaturalGrowthPattern(for: region)
            let adjacentPatterns = surfaceData.getAdjacentRegions(region).compactMap {
                surfaceData.getNaturalGrowthPattern(for: $0)
            }
            
            // Generate directions with natural variation
            for _ in 0..<count {
                let baseDirection = naturalPattern.direction
                let variation = generateNaturalVariation(
                    baseDirection: baseDirection,
                    variance: naturalPattern.variance,
                    adjacentPatterns: adjacentPatterns
                )
                
                directions.append(Direction(
                    angle: variation,
                    region: region
                ))
            }
        }
        
        return directions
    }
    
    private func generateNaturalVariation(
        baseDirection: SIMD3<Float>,
        variance: Float,
        adjacentPatterns: [NaturalPattern]
    ) -> SIMD3<Float> {
        // Start with base direction
        var direction = baseDirection
        
        // Add random variation within natural variance
        let randomAngle = Float.random(in: -variance...variance)
        let perpendicular = normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
        direction = rotate(vector: direction, around: perpendicular, by: randomAngle)
        
        // Blend with adjacent patterns based on confidence
        if !adjacentPatterns.isEmpty {
            let totalConfidence = adjacentPatterns.reduce(0.0) { $0 + $1.confidence }
            
            for pattern in adjacentPatterns {
                let weight = Float(pattern.confidence / totalConfidence) * 0.3 // 30% influence
                direction = normalize(direction + pattern.direction * weight)
            }
        }
        
        return direction
    }
    
    private func rotate(
        vector: SIMD3<Float>,
        around axis: SIMD3<Float>,
        by angle: Float
    ) -> SIMD3<Float> {
        let cosA = cos(angle)
        let sinA = sin(angle)
        
        return vector * cosA +
               cross(axis, vector) * sinA +
               axis * dot(axis, vector) * (1 - cosA)
    }
    
    private func getRegionImportance(_ region: String) -> Double {
        switch region.lowercased() {
        case _ where region.contains("hairline"):
            return 1.2 // Most visible, highest priority
        case _ where region.contains("crown"):
            return 1.1 // High visibility
        case _ where region.contains("temple"):
            return 1.0 // Standard priority
        case _ where region.contains("midscalp"):
            return 0.9 // Lower priority
        default:
            return 1.0
        }
    }
}