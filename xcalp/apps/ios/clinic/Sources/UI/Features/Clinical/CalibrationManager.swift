import Foundation
import simd

final class CalibrationManager {
    static let shared = CalibrationManager()
    
    private var ethnicityProfiles: [String: EthnicityProfile] = [
        "asian": EthnicityProfile(
            growthAngles: RegionalAngles(
                hairline: 65,
                crown: 75,
                temples: 60,
                midScalp: 70
            ),
            densityFactors: RegionalDensityFactors(
                hairline: 1.1,
                crown: 1.0,
                temples: 1.2,
                midScalp: 1.1
            ),
            textureCharacteristics: TextureProfile(
                diameter: 0.08,
                curvature: 0.4,
                variability: 0.3
            )
        ),
        "african": EthnicityProfile(
            growthAngles: RegionalAngles(
                hairline: 45,
                crown: 55,
                temples: 40,
                midScalp: 50
            ),
            densityFactors: RegionalDensityFactors(
                hairline: 0.9,
                crown: 0.9,
                temples: 1.0,
                midScalp: 0.9
            ),
            textureCharacteristics: TextureProfile(
                diameter: 0.12,
                curvature: 0.8,
                variability: 0.5
            )
        ),
        "caucasian": EthnicityProfile(
            growthAngles: RegionalAngles(
                hairline: 55,
                crown: 65,
                temples: 50,
                midScalp: 60
            ),
            densityFactors: RegionalDensityFactors(
                hairline: 1.0,
                crown: 1.0,
                temples: 1.0,
                midScalp: 1.0
            ),
            textureCharacteristics: TextureProfile(
                diameter: 0.06,
                curvature: 0.3,
                variability: 0.2
            )
        )
    ]
    
    private var customProfiles: [String: EthnicityProfile] = [:]
    
    func calibrateGrowthPattern(
        pattern: GrowthPattern,
        region: String,
        ethnicity: String
    ) -> GrowthPattern {
        guard let profile = getProfile(for: ethnicity) else {
            return pattern
        }
        
        let angleAdjustment = profile.growthAngles.getAngle(for: region)
        let adjustedDirection = adjustGrowthAngle(
            pattern.direction,
            by: angleAdjustment
        )
        
        return GrowthPattern(
            direction: adjustedDirection,
            significance: pattern.significance,
            variance: pattern.variance * profile.textureCharacteristics.variability
        )
    }
    
    func calibrateDensity(
        density: Double,
        region: String,
        ethnicity: String
    ) -> Double {
        guard let profile = getProfile(for: ethnicity) else {
            return density
        }
        
        return density * profile.densityFactors.getFactor(for: region)
    }
    
    func addCustomProfile(_ profile: EthnicityProfile, for ethnicity: String) {
        customProfiles[ethnicity.lowercased()] = profile
    }
    
    private func getProfile(for ethnicity: String) -> EthnicityProfile? {
        let key = ethnicity.lowercased()
        return customProfiles[key] ?? ethnicityProfiles[key]
    }
    
    private func adjustGrowthAngle(
        _ direction: SIMD3<Float>,
        by angle: Float
    ) -> SIMD3<Float> {
        let radians = angle * .pi / 180.0
        let rotationAxis = normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
        
        // Apply Rodrigues rotation formula
        let cosAngle = cos(radians)
        let sinAngle = sin(radians)
        
        return direction * cosAngle +
               cross(rotationAxis, direction) * sinAngle +
               rotationAxis * dot(rotationAxis, direction) * (1 - cosAngle)
    }
}

struct EthnicityProfile {
    let growthAngles: RegionalAngles
    let densityFactors: RegionalDensityFactors
    let textureCharacteristics: TextureProfile
}

struct RegionalAngles {
    let hairline: Float
    let crown: Float
    let temples: Float
    let midScalp: Float
    
    func getAngle(for region: String) -> Float {
        switch region.lowercased() {
        case let r where r.contains("hairline"): return hairline
        case let r where r.contains("crown"): return crown
        case let r where r.contains("temple"): return temples
        case let r where r.contains("midscalp"): return midScalp
        default: return 60.0 // Default angle
        }
    }
}

struct RegionalDensityFactors {
    let hairline: Double
    let crown: Double
    let temples: Double
    let midScalp: Double
    
    func getFactor(for region: String) -> Double {
        switch region.lowercased() {
        case let r where r.contains("hairline"): return hairline
        case let r where r.contains("crown"): return crown
        case let r where r.contains("temple"): return temples
        case let r where r.contains("midscalp"): return midScalp
        default: return 1.0
        }
    }
}

struct TextureProfile {
    let diameter: Double  // Average hair diameter in mm
    let curvature: Double // 0-1 scale
    let variability: Double // Natural variation factor
}