import Foundation

struct ClinicalCase: Codable {
    let id: UUID
    let patientId: UUID
    let clinicianId: UUID
    let createdAt: Date
    let updatedAt: Date
    var status: CaseStatus
    
    // Workflow components
    var patientConsents: Set<ConsentType>?
    var consentDates: [ConsentType: Date]
    var medicalHistory: MedicalHistory?
    var preoperativePhotos: [PreoperativePhoto]?
    var scan: ScanData?
    var planningDocumentation: PlanningDocumentation?
    var postOperativeInstructions: PostOperativeInstructions?
    var culturalAssessment: CulturalAssessment?
    
    enum CaseStatus: String, Codable {
        case draft
        case inProgress
        case completed
        case archived
        case cancelled
    }
}

struct MedicalHistory: Codable {
    var fields: [String: String]
    let lastUpdated: Date
    
    subscript(field: String) -> String? {
        return fields[field]
    }
}

struct PreoperativePhoto: Codable {
    let id: UUID
    let angle: Int
    let imageUrl: URL
    let qualityScore: Float
    let metadata: PhotoMetadata
    
    struct PhotoMetadata: Codable {
        let timestamp: Date
        let deviceInfo: String
        let lightingConditions: String
        let resolution: String
    }
}

struct PlanningDocumentation: Codable {
    let donorAreaAnalysis: DonorAreaAnalysis?
    let recipientAreaAnalysis: RecipientAreaAnalysis?
    let graftCountEstimation: GraftCountEstimation?
    let futureProjections: FutureProjections?
    let culturalPreferences: CulturalPreferences?
    let textureConsiderations: TextureConsiderations?
    
    var hasDonorAreaAnalysis: Bool { donorAreaAnalysis != nil }
    var hasRecipientAreaAnalysis: Bool { recipientAreaAnalysis != nil }
    var hasGraftCountEstimation: Bool { graftCountEstimation != nil }
    var hasFutureProjections: Bool { futureProjections != nil }
    var hasCulturalPreferences: Bool { culturalPreferences != nil }
    var hasTextureConsiderations: Bool { textureConsiderations != nil }
}

struct PostOperativeInstructions: Codable {
    let version: Int
    let defaultLanguage: String
    let supportedLanguages: Set<String>
    let instructions: [String: [Instruction]]
    
    var hasDefaultLanguage: Bool {
        instructions[defaultLanguage] != nil
    }
    
    struct Instruction: Codable {
        let day: Int
        let title: String
        let description: String
        let importance: ImportanceLevel
        
        enum ImportanceLevel: String, Codable {
            case critical
            case important
            case normal
        }
    }
}

struct DonorAreaAnalysis: Codable {
    let density: Float
    let area: Float
    let maximumGrafts: Int
    let quality: String
    let notes: String?
}

struct RecipientAreaAnalysis: Codable {
    let area: Float
    let requiredDensity: Float
    let estimatedGrafts: Int
    let zones: [RecipientZone]
    
    struct RecipientZone: Codable {
        let name: String
        let area: Float
        let priority: Int
        let plannedDensity: Float
    }
}

struct GraftCountEstimation: Codable {
    let totalGrafts: Int
    let safetyMargin: Float
    let distribution: [GraftDistribution]
    
    struct GraftDistribution: Codable {
        let zone: String
        let count: Int
        let density: Float
    }
}

struct FutureProjections: Codable {
    let timeframes: [Timeframe]
    let maintenanceRecommendations: [String]
    
    struct Timeframe: Codable {
        let months: Int
        let expectedDensity: Float
        let visualRepresentation: URL?
    }
}

struct TextureConsiderations: Codable {
    let existingTexture: TextureMetrics
    let targetTexture: TextureMetrics
    let blendingStrategy: String
    let specialInstructions: [String]
}