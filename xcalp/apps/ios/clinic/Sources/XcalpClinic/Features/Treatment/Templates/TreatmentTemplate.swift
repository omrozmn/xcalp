import Foundation

/// A template for hair transplant treatment planning
struct TreatmentTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let parameters: TreatmentParameters
    let createdAt: Date
    let updatedAt: Date
    
    /// Treatment-specific parameters
    struct TreatmentParameters: Codable {
        let targetDensity: Double // grafts per cm²
        let safetyMargins: Margins // mm
        let anglePreferences: AnglePreferences
        let regionSpecifications: RegionSpecifications
    }
    
    struct Margins: Codable {
        let anterior: Double
        let posterior: Double
        let lateral: Double
    }
    
    struct AnglePreferences: Codable {
        let crown: Double // degrees
        let hairline: Double // degrees
        let temporal: Double // degrees
    }
    
    struct RegionSpecifications: Codable {
        let donor: DonorRegion
        let recipient: RecipientRegion
    }
    
    struct DonorRegion: Codable {
        let safeExtractionDepth: Double // mm
        let maxGraftDensity: Double // grafts per cm²
        let minimumFollicleSpacing: Double // mm
    }
    
    struct RecipientRegion: Codable {
        let targetHairlinePosition: Double // mm from reference point
        let naturalAngleVariation: Double // degrees ±
        let densityGradient: Double // grafts per cm² variation
    }
}