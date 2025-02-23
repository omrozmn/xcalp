import Foundation
import SceneKit

class TreatmentPlanningService {
    private let templateManager: TemplateManager
    
    init(templateManager: TemplateManager = TemplateManager()) {
        self.templateManager = templateManager
    }
    
    func applyTemplate(_ template: TreatmentTemplate, to scanData: ScanData) throws -> TreatmentPlan {
        // Calculate actual graft counts based on surface area
        let recipientArea = scanData.calculateRecipientArea()
        let totalGrafts = Int(recipientArea * template.parameters.targetDensity)
        
        // Apply safety margins
        let margins = template.parameters.safetyMargins
        let safeRegion = scanData.calculateSafeRegion(
            anterior: margins.anterior,
            posterior: margins.posterior,
            lateral: margins.lateral
        )
        
        // Apply angle preferences
        let angleMap = generateAngleMap(
            from: template.parameters.anglePreferences,
            for: safeRegion,
            naturalVariation: template.parameters.regionSpecifications.recipient.naturalAngleVariation
        )
        
        // Generate density distribution
        let densityMap = generateDensityMap(
            targetDensity: template.parameters.targetDensity,
            gradient: template.parameters.regionSpecifications.recipient.densityGradient,
            region: safeRegion
        )
        
        return TreatmentPlan(
            templateId: template.id,
            scanId: scanData.id,
            safeRegion: safeRegion,
            totalGrafts: totalGrafts,
            angleMap: angleMap,
            densityMap: densityMap,
            createdAt: Date()
        )
    }
    
    private func generateAngleMap(
        from preferences: TreatmentTemplate.AnglePreferences,
        for region: SafeRegion,
        naturalVariation: Double
    ) -> AngleMap {
        // Create angle map with natural variation
        let baseAngles = AngleMap(
            crown: preferences.crown,
            hairline: preferences.hairline,
            temporal: preferences.temporal
        )
        
        return baseAngles.addingRandomVariation(
            amount: naturalVariation,
            seed: UInt64(Date().timeIntervalSince1970)
        )
    }
    
    private func generateDensityMap(
        targetDensity: Double,
        gradient: Double,
        region: SafeRegion
    ) -> DensityMap {
        // Generate density distribution with gradual falloff
        return DensityMap(
            baseValue: targetDensity,
            gradient: gradient,
            region: region
        )
    }
}

// Supporting types
struct ScanData {
    let id: UUID
    let mesh: SCNGeometry
    let surfaceArea: Double
    
    func calculateRecipientArea() -> Double {
        // Calculate available surface area for transplantation
        return surfaceArea * 0.7 // Typical usable area
    }
    
    func calculateSafeRegion(anterior: Double, posterior: Double, lateral: Double) -> SafeRegion {
        // Calculate safe region based on margins
        return SafeRegion(
            bounds: mesh.boundingBox,
            anteriorMargin: anterior,
            posteriorMargin: posterior,
            lateralMargin: lateral
        )
    }
}

struct TreatmentPlan {
    let templateId: UUID
    let scanId: UUID
    let safeRegion: SafeRegion
    let totalGrafts: Int
    let angleMap: AngleMap
    let densityMap: DensityMap
    let createdAt: Date
}

struct SafeRegion {
    let bounds: (min: SCNVector3, max: SCNVector3)
    let anteriorMargin: Double
    let posteriorMargin: Double
    let lateralMargin: Double
}

struct AngleMap {
    let crown: Double
    let hairline: Double
    let temporal: Double
    
    func addingRandomVariation(amount: Double, seed: UInt64) -> AngleMap {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return AngleMap(
            crown: crown + Double.random(in: -amount...amount, using: &rng),
            hairline: hairline + Double.random(in: -amount...amount, using: &rng),
            temporal: temporal + Double.random(in: -amount...amount, using: &rng)
        )
    }
}

struct DensityMap {
    let baseValue: Double
    let gradient: Double
    let region: SafeRegion
    
    func densityAt(point: SCNVector3) -> Double {
        // Calculate density at given point with gradual falloff
        let distanceFromCenter = sqrt(
            pow(point.x, 2) +
            pow(point.y, 2) +
            pow(point.z, 2)
        )
        
        return baseValue * (1.0 - (distanceFromCenter * gradient))
    }
}

// Random number generator for consistent variation
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var rng: UInt64
    
    init(seed: UInt64) {
        rng = seed
    }
    
    mutating func next() -> UInt64 {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return rng
    }
}