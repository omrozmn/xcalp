import Foundation
import CoreML
import Vision

public final class GrowthProjector {
    private let growthModel: HairGrowthModel
    private let environmentalFactors: EnvironmentalFactors
    
    public init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        self.growthModel = try HairGrowthModel(configuration: config)
        self.environmentalFactors = EnvironmentalFactors()
    }
    
    public func calculateProjections(months: [Int]) async throws -> [GrowthProjection] {
        var projections: [GrowthProjection] = []
        
        // Get base metrics
        let baseMetrics = try await growthModel.getCurrentMetrics()
        
        // Calculate projections for each time point
        for month in months {
            let projection = try await calculateProjection(
                from: baseMetrics,
                atMonth: month
            )
            projections.append(projection)
        }
        
        return projections
    }
    
    public func calculateProjectionsWithStress(months: [Int]) async throws -> [GrowthProjection] {
        var projections: [GrowthProjection] = []
        
        // Get base metrics with stress factor applied
        let baseMetrics = try await growthModel.getCurrentMetrics()
        let stressedMetrics = GrowthMetrics(
            density: baseMetrics.density * 0.95,  // 5% reduction due to stress
            thickness: baseMetrics.thickness * 0.95,
            length: baseMetrics.length * 0.95,
            coverage: baseMetrics.coverage * 0.95,
            healthScore: baseMetrics.healthScore * 0.90  // 10% reduction in health
        )
        
        // Calculate projections with stress impact
        for month in months {
            let projection = try await calculateProjection(
                from: stressedMetrics,
                atMonth: month,
                withStressImpact: true
            )
            projections.append(projection)
        }
        
        return projections
    }
    
    private func calculateProjection(
        from baseMetrics: GrowthMetrics,
        atMonth month: Int,
        withStressImpact: Bool = false
    ) async throws -> GrowthProjection {
        // Apply growth model with stress consideration
        let growthPhase = determineGrowthPhase(forMonth: month)
        var environmentalImpact = try environmentalFactors.calculateImpact(forMonth: month)
        
        // Apply additional stress impact if needed
        if withStressImpact {
            environmentalImpact *= 0.85 // 15% reduction in environmental factors
        }
        
        let projectedMetrics = try await growthModel.projectGrowth(
            from: baseMetrics,
            phase: growthPhase,
            environmentalFactors: environmentalImpact,
            timePoint: month
        )
        
        return GrowthProjection(
            month: month,
            density: projectedMetrics.density,
            thickness: projectedMetrics.thickness,
            length: projectedMetrics.length,
            coverage: projectedMetrics.coverage,
            growth: calculateGrowthRate(
                initial: baseMetrics.density,
                final: projectedMetrics.density,
                months: month
            )
        )
    }
    
    private func determineGrowthPhase(forMonth month: Int) -> GrowthPhase {
        switch month {
        case 0...1:
            return .telogen
        case 2...3:
            return .earlyAnagen
        case 4...8:
            return .midAnagen
        default:
            return .lateAnagen
        }
    }
    
    private func calculateGrowthRate(initial: Float, final: Float, months: Int) -> Float {
        guard months > 0 else { return 0 }
        return (final - initial) / Float(months)
    }
}

public struct GrowthProjection {
    public let month: Int
    public let density: Float    // follicles/cm²
    public let thickness: Float  // mm
    public let length: Float     // mm
    public let coverage: Float   // percentage
    public let growth: Float     // follicles/cm²/month
}

private struct GrowthMetrics {
    let density: Float
    let thickness: Float
    let length: Float
    let coverage: Float
    let healthScore: Float
}

private enum GrowthPhase {
    case telogen      // Resting phase
    case earlyAnagen  // Early growth
    case midAnagen    // Active growth
    case lateAnagen   // Mature growth
}

private struct EnvironmentalFactors {
    private let seasonalVariation: Float = 0.1  // ±10% variation
    private let stressImpact: Float = -0.05     // -5% impact
    private let nutritionImpact: Float = 0.08   // +8% impact
    
    func calculateImpact(forMonth month: Int) throws -> Float {
        let baseImpact: Float = 1.0
        
        // Apply seasonal variation
        let seasonalPhase = Float(month % 12) / 12.0 * 2.0 * .pi
        let seasonalFactor = 1.0 + seasonalVariation * sin(seasonalPhase)
        
        // Apply other factors
        let stressFactor = 1.0 + stressImpact
        let nutritionFactor = 1.0 + nutritionImpact
        
        return baseImpact * seasonalFactor * stressFactor * nutritionFactor
    }
}