import Foundation

class PatientProfileManager {
    static let shared = PatientProfileManager()
    
    private let regionManager = RegionalComplianceManager.shared
    private let sensitivityManager = SensitivityGuidelineManager.shared
    private let culturalAnalyzer = CulturalPatternAnalyzer.shared
    private let analytics = AnalyticsService.shared
    
    // Regional profile configurations
    private var profileConfigs: [Region: ProfileConfig] = [
        .unitedStates: .init(
            requiredFields: [
                .name,
                .dateOfBirth,
                .contact,
                .medicalHistory,
                .insurance
            ],
            optionalFields: [
                .ethnicity,
                .lifestyle,
                .preferences
            ],
            dataRetention: 2190,  // 6 years
            privacyLevel: .high,
            dataExport: true
        ),
        .europeanUnion: .init(
            requiredFields: [
                .name,
                .dateOfBirth,
                .contact,
                .medicalHistory,
                .gdprConsent
            ],
            optionalFields: [
                .ethnicity,
                .lifestyle,
                .preferences,
                .insurance
            ],
            dataRetention: 3650,  // 10 years
            privacyLevel: .high,
            dataExport: true,
            dataDeletion: true
        ),
        .southAsia: .init(
            requiredFields: [
                .name,
                .dateOfBirth,
                .contact,
                .medicalHistory,
                .familyDetails,
                .culturalPreferences
            ],
            optionalFields: [
                .lifestyle,
                .insurance,
                .communityAffiliation
            ],
            dataRetention: 1825,  // 5 years
            privacyLevel: .high,
            culturalRequirements: [
                .familyConsent,
                .religiousPreferences,
                .traditionalMedicine
            ]
        ),
        .mediterranean: .init(
            requiredFields: [
                .name,
                .dateOfBirth,
                .contact,
                .medicalHistory,
                .familyDetails,
                .culturalPreferences
            ],
            optionalFields: [
                .lifestyle,
                .insurance,
                .religiousPreferences
            ],
            dataRetention: 1825,  // 5 years
            privacyLevel: .high,
            culturalRequirements: [
                .familyConsent,
                .religiousPreferences
            ]
        ),
        .africanDescent: .init(
            requiredFields: [
                .name,
                .dateOfBirth,
                .contact,
                .medicalHistory,
                .culturalPreferences,
                .communityAffiliation
            ],
            optionalFields: [
                .lifestyle,
                .insurance,
                .familyDetails,
                .traditionalPractices
            ],
            dataRetention: 1825,  // 5 years
            privacyLevel: .high,
            culturalRequirements: [
                .communityConsent,
                .culturalHeritage,
                .traditionalPractices
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func createProfile(_ profile: PatientProfile) async throws -> PatientProfile {
        let region = regionManager.getCurrentRegion()
        guard let config = profileConfigs[region] else {
            throw ProfileError.unsupportedRegion(region)
        }
        
        // Validate required fields
        try validateRequiredFields(profile, config: config)
        
        // Apply cultural requirements if applicable
        var culturalProfile = profile
        if let requirements = config.culturalRequirements {
            culturalProfile = try await applyCulturalRequirements(
                profile,
                requirements: requirements
            )
        }
        
        // Validate sensitivity
        try sensitivityManager.validateDataSensitivity(
            culturalProfile.sensitiveData
        )
        
        // Store profile
        let storedProfile = try await storeProfile(culturalProfile)
        
        // Track profile creation
        trackProfileCreation(storedProfile, region: region)
        
        return storedProfile
    }
    
    func updateProfile(
        _ profile: PatientProfile,
        with updates: ProfileUpdates
    ) async throws -> PatientProfile {
        let region = regionManager.getCurrentRegion()
        guard let config = profileConfigs[region] else {
            throw ProfileError.unsupportedRegion(region)
        }
        
        // Validate updates
        try validateProfileUpdates(updates, config: config)
        
        // Apply updates
        var updatedProfile = try await applyUpdates(
            to: profile,
            updates: updates
        )
        
        // Apply cultural requirements if applicable
        if let requirements = config.culturalRequirements {
            updatedProfile = try await applyCulturalRequirements(
                updatedProfile,
                requirements: requirements
            )
        }
        
        // Validate sensitivity
        try sensitivityManager.validateDataSensitivity(
            updatedProfile.sensitiveData
        )
        
        // Store updated profile
        let storedProfile = try await storeProfile(updatedProfile)
        
        // Track profile update
        trackProfileUpdate(storedProfile, updates: updates)
        
        return storedProfile
    }
    
    func deleteProfile(_ profileId: UUID) async throws {
        let region = regionManager.getCurrentRegion()
        guard let config = profileConfigs[region] else {
            throw ProfileError.unsupportedRegion(region)
        }
        
        // Check if deletion is allowed
        guard config.dataDeletion == true else {
            throw ProfileError.deletionNotAllowed
        }
        
        // Delete profile data
        try await deleteProfileData(profileId)
        
        // Track deletion
        trackProfileDeletion(profileId, region: region)
    }
    
    func exportProfile(_ profileId: UUID) async throws -> ProfileExport {
        let region = regionManager.getCurrentRegion()
        guard let config = profileConfigs[region] else {
            throw ProfileError.unsupportedRegion(region)
        }
        
        // Check if export is allowed
        guard config.dataExport == true else {
            throw ProfileError.exportNotAllowed
        }
        
        // Fetch profile
        let profile = try await fetchProfile(profileId)
        
        // Prepare export data
        let export = try prepareProfileExport(
            profile,
            config: config
        )
        
        // Track export
        trackProfileExport(profileId, region: region)
        
        return export
    }
    
    // MARK: - Private Methods
    
    private func validateRequiredFields(
        _ profile: PatientProfile,
        config: ProfileConfig
    ) throws {
        for field in config.requiredFields {
            switch field {
            case .name:
                guard !profile.name.isEmpty else {
                    throw ProfileError.missingRequiredField(.name)
                }
            case .dateOfBirth:
                guard profile.dateOfBirth != nil else {
                    throw ProfileError.missingRequiredField(.dateOfBirth)
                }
            case .contact:
                guard profile.contactInformation != nil else {
                    throw ProfileError.missingRequiredField(.contact)
                }
            case .medicalHistory:
                guard profile.medicalHistory != nil else {
                    throw ProfileError.missingRequiredField(.medicalHistory)
                }
            case .familyDetails:
                guard profile.familyDetails != nil else {
                    throw ProfileError.missingRequiredField(.familyDetails)
                }
            case .culturalPreferences:
                guard profile.culturalPreferences != nil else {
                    throw ProfileError.missingRequiredField(.culturalPreferences)
                }
            case .insurance:
                guard profile.insuranceDetails != nil else {
                    throw ProfileError.missingRequiredField(.insurance)
                }
            case .gdprConsent:
                guard profile.gdprConsent != nil else {
                    throw ProfileError.missingRequiredField(.gdprConsent)
                }
            case .communityAffiliation:
                guard profile.communityAffiliation != nil else {
                    throw ProfileError.missingRequiredField(.communityAffiliation)
                }
            }
        }
    }
    
    private func applyCulturalRequirements(
        _ profile: PatientProfile,
        requirements: Set<CulturalRequirement>
    ) async throws -> PatientProfile {
        var culturalProfile = profile
        
        for requirement in requirements {
            switch requirement {
            case .familyConsent:
                try validateFamilyConsent(profile)
                
            case .religiousPreferences:
                if let preferences = profile.religiousPreferences {
                    culturalProfile.culturalContext["religion"] = preferences
                }
                
            case .traditionalMedicine:
                if let practices = profile.traditionalPractices {
                    culturalProfile.culturalContext["traditional_medicine"] = practices
                }
                
            case .communityConsent:
                try validateCommunityConsent(profile)
                
            case .culturalHeritage:
                if let heritage = profile.culturalHeritage {
                    culturalProfile.culturalContext["heritage"] = heritage
                }
                
            case .traditionalPractices:
                if let practices = profile.traditionalPractices {
                    culturalProfile.culturalContext["practices"] = practices
                }
            }
        }
        
        return culturalProfile
    }
    
    private func trackProfileCreation(
        _ profile: PatientProfile,
        region: Region
    ) {
        analytics.trackEvent(
            category: .profile,
            action: "creation",
            label: region.rawValue,
            value: 1,
            metadata: [
                "profile_id": profile.id.uuidString,
                "fields_count": String(profile.fieldCount),
                "has_cultural": String(profile.hasCulturalData)
            ]
        )
    }
}

// MARK: - Supporting Types

struct ProfileConfig {
    let requiredFields: Set<ProfileField>
    let optionalFields: Set<ProfileField>
    let dataRetention: Int
    let privacyLevel: SensitivityLevel
    let culturalRequirements: Set<CulturalRequirement>?
    let dataExport: Bool?
    let dataDeletion: Bool?
}

struct PatientProfile {
    let id: UUID
    var name: String
    var dateOfBirth: Date?
    var contactInformation: ContactInfo?
    var medicalHistory: MedicalHistory?
    var familyDetails: FamilyDetails?
    var culturalPreferences: CulturalPreferences?
    var insuranceDetails: InsuranceDetails?
    var gdprConsent: GDPRConsent?
    var communityAffiliation: CommunityAffiliation?
    var religiousPreferences: ReligiousPreferences?
    var traditionalPractices: TraditionalPractices?
    var culturalHeritage: CulturalHeritage?
    var culturalContext: [String: Any]
    var sensitiveData: SensitiveData
    let createdAt: Date
    var updatedAt: Date
    
    var fieldCount: Int {
        var count = 1  // name is always present
        if dateOfBirth != nil { count += 1 }
        if contactInformation != nil { count += 1 }
        if medicalHistory != nil { count += 1 }
        if familyDetails != nil { count += 1 }
        if culturalPreferences != nil { count += 1 }
        if insuranceDetails != nil { count += 1 }
        if gdprConsent != nil { count += 1 }
        if communityAffiliation != nil { count += 1 }
        if religiousPreferences != nil { count += 1 }
        if traditionalPractices != nil { count += 1 }
        if culturalHeritage != nil { count += 1 }
        return count
    }
    
    var hasCulturalData: Bool {
        return culturalPreferences != nil ||
            religiousPreferences != nil ||
            traditionalPractices != nil ||
            culturalHeritage != nil ||
            !culturalContext.isEmpty
    }
}

enum ProfileField {
    case name
    case dateOfBirth
    case contact
    case medicalHistory
    case familyDetails
    case culturalPreferences
    case insurance
    case gdprConsent
    case communityAffiliation
}

enum CulturalRequirement {
    case familyConsent
    case religiousPreferences
    case traditionalMedicine
    case communityConsent
    case culturalHeritage
    case traditionalPractices
}

struct ProfileUpdates {
    let fieldUpdates: [ProfileField: Any]
    let culturalUpdates: [String: Any]?
    let sensitivityUpdates: [String: SensitivityLevel]?
}

struct ProfileExport {
    let profileData: PatientProfile
    let exportDate: Date
    let exportFormat: ExportFormat
    let dataCategories: Set<DataCategory>
    
    enum ExportFormat {
        case json
        case pdf
        case hl7
    }
}

enum ProfileError: LocalizedError {
    case unsupportedRegion(Region)
    case missingRequiredField(ProfileField)
    case invalidFieldValue(ProfileField, String)
    case deletionNotAllowed
    case exportNotAllowed
    case culturalRequirementNotMet(CulturalRequirement)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Patient profile configuration not available for region: \(region)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidFieldValue(let field, let reason):
            return "Invalid value for field \(field): \(reason)"
        case .deletionNotAllowed:
            return "Profile deletion is not allowed in this region"
        case .exportNotAllowed:
            return "Profile export is not allowed in this region"
        case .culturalRequirementNotMet(let requirement):
            return "Cultural requirement not met: \(requirement)"
        }
    }
}