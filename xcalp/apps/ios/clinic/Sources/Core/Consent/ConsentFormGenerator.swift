import Foundation

class ConsentFormGenerator {
    static let shared = ConsentFormGenerator()
    
    private let regionManager = RegionalComplianceManager.shared
    private let languageFormatter = LanguageStyleFormatter.shared
    private let analytics = AnalyticsService.shared
    
    // Regional consent configurations
    private var consentConfigs: [Region: ConsentConfig] = [
        .unitedStates: .init(
            requiredForms: [.hipaa, .procedure, .photography],
            validityPeriod: 365,  // days
            requiredSignatures: [.patient, .physician],
            languageRequirements: ["en"],
            legalRequirements: [
                .optOut: true,
                .revocation: true,
                .dataRights: true
            ]
        ),
        .europeanUnion: .init(
            requiredForms: [.gdpr, .procedure, .photography, .dataProcessing],
            validityPeriod: 365,
            requiredSignatures: [.patient, .physician, .dataController],
            languageRequirements: ["local", "en"],
            legalRequirements: [
                .optOut: true,
                .revocation: true,
                .dataRights: true,
                .dataPortability: true
            ]
        ),
        .southAsia: .init(
            requiredForms: [
                .procedure,
                .photography,
                .culturalConsideration,
                .familyConsent
            ],
            validityPeriod: 180,
            requiredSignatures: [
                .patient,
                .physician,
                .familyMember,
                .witness
            ],
            languageRequirements: ["local", "en"],
            legalRequirements: [
                .optOut: true,
                .revocation: true,
                .familyRights: true
            ],
            culturalRequirements: [
                .familyInvolvement,
                .religiousConsideration,
                .communityAwareness
            ]
        ),
        .mediterranean: .init(
            requiredForms: [
                .procedure,
                .photography,
                .culturalConsideration,
                .familyConsent
            ],
            validityPeriod: 365,
            requiredSignatures: [
                .patient,
                .physician,
                .familyMember
            ],
            languageRequirements: ["local", "en"],
            legalRequirements: [
                .optOut: true,
                .revocation: true,
                .familyRights: true
            ],
            culturalRequirements: [
                .familyInvolvement,
                .religiousConsideration
            ]
        ),
        .africanDescent: .init(
            requiredForms: [
                .procedure,
                .photography,
                .culturalConsideration,
                .communityAwareness
            ],
            validityPeriod: 180,
            requiredSignatures: [
                .patient,
                .physician,
                .communityCounselor
            ],
            languageRequirements: ["local", "en"],
            legalRequirements: [
                .optOut: true,
                .revocation: true,
                .culturalRights: true
            ],
            culturalRequirements: [
                .communityAwareness,
                .culturalHeritage,
                .traditionalPractices
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func generateConsentForms(
        for patient: PatientProfile,
        procedure: ProcedureType
    ) async throws -> ConsentPackage {
        let region = regionManager.getCurrentRegion()
        guard let config = consentConfigs[region] else {
            throw ConsentError.unsupportedRegion(region)
        }
        
        var forms: [ConsentForm] = []
        
        // Generate required forms
        for formType in config.requiredForms {
            let form = try await generateForm(
                type: formType,
                patient: patient,
                procedure: procedure,
                config: config
            )
            forms.append(form)
        }
        
        // Add cultural forms if required
        if let culturalRequirements = config.culturalRequirements {
            let culturalForms = try await generateCulturalForms(
                requirements: culturalRequirements,
                patient: patient,
                procedure: procedure
            )
            forms.append(contentsOf: culturalForms)
        }
        
        let package = ConsentPackage(
            id: UUID(),
            patientId: patient.id,
            forms: forms,
            validityPeriod: config.validityPeriod,
            requiredSignatures: config.requiredSignatures,
            createdAt: Date()
        )
        
        // Track package generation
        trackPackageGeneration(package, region: region)
        
        return package
    }
    
    func validateConsentPackage(_ package: ConsentPackage) throws {
        let region = regionManager.getCurrentRegion()
        guard let config = consentConfigs[region] else {
            throw ConsentError.unsupportedRegion(region)
        }
        
        // Validate required forms
        try validateRequiredForms(
            package.forms,
            required: config.requiredForms
        )
        
        // Validate signatures
        try validateSignatures(
            package.signatures,
            required: config.requiredSignatures
        )
        
        // Validate language requirements
        try validateLanguages(
            package.forms,
            required: config.languageRequirements
        )
        
        // Validate cultural requirements if applicable
        if let culturalRequirements = config.culturalRequirements {
            try validateCulturalRequirements(
                package,
                required: culturalRequirements
            )
        }
        
        // Validate expiration
        try validateExpiration(
            package,
            validityPeriod: config.validityPeriod
        )
    }
    
    func updateConsentForms(
        _ package: ConsentPackage,
        with updates: ConsentUpdates
    ) async throws -> ConsentPackage {
        var updatedPackage = package
        
        // Update forms
        for (formId, update) in updates.formUpdates {
            try await updateForm(
                in: &updatedPackage,
                formId: formId,
                update: update
            )
        }
        
        // Add new signatures
        for signature in updates.newSignatures {
            try addSignature(
                to: &updatedPackage,
                signature: signature
            )
        }
        
        // Update metadata
        updatedPackage.metadata.merge(
            updates.metadataUpdates
        ) { _, new in new }
        
        // Track updates
        trackPackageUpdate(updatedPackage, updates: updates)
        
        return updatedPackage
    }
    
    // MARK: - Private Methods
    
    private func generateForm(
        type: ConsentFormType,
        patient: PatientProfile,
        procedure: ProcedureType,
        config: ConsentConfig
    ) async throws -> ConsentForm {
        // Generate base content
        var content = try await generateBaseContent(
            type: type,
            patient: patient,
            procedure: procedure
        )
        
        // Format for cultural sensitivity
        content = try languageFormatter.formatText(
            content,
            context: .init(
                identifier: "consent_form",
                type: .consultation,
                userData: patient.culturalContext
            )
        )
        
        // Add legal requirements
        content = addLegalRequirements(
            to: content,
            requirements: config.legalRequirements
        )
        
        return ConsentForm(
            id: UUID(),
            type: type,
            content: content,
            language: patient.preferredLanguage,
            version: AppConfig.current.consentFormVersion,
            createdAt: Date()
        )
    }
    
    private func generateCulturalForms(
        requirements: Set<CulturalRequirement>,
        patient: PatientProfile,
        procedure: ProcedureType
    ) async throws -> [ConsentForm] {
        var culturalForms: [ConsentForm] = []
        
        for requirement in requirements {
            switch requirement {
            case .familyInvolvement:
                let form = try await generateFamilyInvolvementForm(
                    patient: patient,
                    procedure: procedure
                )
                culturalForms.append(form)
                
            case .religiousConsideration:
                if let religion = patient.religiousPreferences {
                    let form = try await generateReligiousConsiderationForm(
                        religion: religion,
                        procedure: procedure
                    )
                    culturalForms.append(form)
                }
                
            case .communityAwareness:
                let form = try await generateCommunityAwarenessForm(
                    patient: patient,
                    procedure: procedure
                )
                culturalForms.append(form)
                
            case .culturalHeritage:
                let form = try await generateCulturalHeritageForm(
                    patient: patient,
                    procedure: procedure
                )
                culturalForms.append(form)
                
            case .traditionalPractices:
                let form = try await generateTraditionalPracticesForm(
                    patient: patient,
                    procedure: procedure
                )
                culturalForms.append(form)
            }
        }
        
        return culturalForms
    }
    
    private func trackPackageGeneration(
        _ package: ConsentPackage,
        region: Region
    ) {
        analytics.trackEvent(
            category: .consent,
            action: "package_generation",
            label: region.rawValue,
            value: package.forms.count,
            metadata: [
                "patient_id": package.patientId.uuidString,
                "form_types": package.forms.map { $0.type.rawValue }.joined(separator: ","),
                "validity_period": String(package.validityPeriod)
            ]
        )
    }
}

// MARK: - Supporting Types

struct ConsentConfig {
    let requiredForms: Set<ConsentFormType>
    let validityPeriod: Int
    let requiredSignatures: Set<SignatureType>
    let languageRequirements: [String]
    let legalRequirements: [String: Bool]
    let culturalRequirements: Set<CulturalRequirement>?
}

struct ConsentPackage {
    let id: UUID
    let patientId: UUID
    var forms: [ConsentForm]
    let validityPeriod: Int
    let requiredSignatures: Set<SignatureType>
    var signatures: [Signature]
    var metadata: [String: Any]
    let createdAt: Date
}

struct ConsentForm {
    let id: UUID
    let type: ConsentFormType
    var content: String
    let language: String
    let version: Int
    let createdAt: Date
}

enum ConsentFormType: String {
    case hipaa = "HIPAA"
    case gdpr = "GDPR"
    case procedure = "Procedure"
    case photography = "Photography"
    case dataProcessing = "Data Processing"
    case culturalConsideration = "Cultural Consideration"
    case familyConsent = "Family Consent"
    case communityAwareness = "Community Awareness"
}

enum SignatureType {
    case patient
    case physician
    case familyMember
    case witness
    case dataController
    case communityCounselor
}

enum CulturalRequirement {
    case familyInvolvement
    case religiousConsideration
    case communityAwareness
    case culturalHeritage
    case traditionalPractices
}

struct ConsentUpdates {
    let formUpdates: [UUID: FormUpdate]
    let newSignatures: [Signature]
    let metadataUpdates: [String: Any]
    
    struct FormUpdate {
        let content: String?
        let signatures: [Signature]?
        let metadata: [String: Any]?
    }
}

enum ConsentError: LocalizedError {
    case unsupportedRegion(Region)
    case missingRequiredForm(ConsentFormType)
    case missingSignature(SignatureType)
    case invalidLanguage(String)
    case culturalRequirementMissing(CulturalRequirement)
    case expired(daysAgo: Int)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Consent forms not configured for region: \(region)"
        case .missingRequiredForm(let type):
            return "Missing required consent form: \(type)"
        case .missingSignature(let type):
            return "Missing required signature: \(type)"
        case .invalidLanguage(let language):
            return "Invalid or missing language: \(language)"
        case .culturalRequirementMissing(let requirement):
            return "Missing cultural requirement: \(requirement)"
        case .expired(let days):
            return "Consent package expired \(days) days ago"
        }
    }
}