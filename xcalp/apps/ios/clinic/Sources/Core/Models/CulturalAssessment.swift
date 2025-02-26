import Foundation

struct CulturalAssessment: Codable {
    let id: UUID
    let patientId: UUID
    let region: Region
    let religiousConsiderations: ReligiousConsiderations?
    let traditionalStylePreferences: [TraditionalStyle]
    let familyPatternHistory: FamilyPatternHistory?
    let hairTextureAnalysis: HairTextureAnalysis?
    let documentationTimestamp: Date
    
    var religiousConsiderationsDocumented: Bool {
        religiousConsiderations != nil
    }
    
    var traditionalStylesDocumented: Bool {
        !traditionalStylePreferences.isEmpty
    }
    
    var familyPatternsDocumented: Bool {
        familyPatternHistory != nil
    }
    
    var hairTextureDocumented: Bool {
        hairTextureAnalysis != nil
    }
}

struct ReligiousConsiderations: Codable {
    let religion: Religion
    let requirements: [String]
    let restrictions: [String]
    let notes: String?
}

struct FamilyPatternHistory: Codable {
    let maternalPattern: HairPattern
    let paternalPattern: HairPattern
    let significantRelatives: [RelativeHairPattern]
    let inheritanceNotes: String?
}

struct RelativeHairPattern: Codable {
    let relation: String
    let pattern: HairPattern
    let ageOfOnset: Int?
}

struct HairPattern: Codable {
    let type: GrowthPattern
    let density: Float
    let texture: TextureMetrics
    let ageOfOnset: Int?
    let progressionNotes: String?
}

struct HairTextureAnalysis: Codable {
    let baseTexture: TextureMetrics
    let variations: [TextureVariation]
    let scaleMeasurements: [ScaleMeasurement]
    let analysisNotes: String?
}

struct TextureVariation: Codable {
    let region: String
    let texture: TextureMetrics
    let coverage: Float // percentage
}

struct ScaleMeasurement: Codable {
    let region: String
    let diameter: Float // micrometers
    let cuticlePattern: String
    let notes: String?
}