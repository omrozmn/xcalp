import Foundation

class RegionalComplianceManager {
    static let shared = RegionalComplianceManager()
    
    private var currentRegion: Region
    private var complianceRules: [Region: Set<ComplianceRule>] = [
        .unitedStates: [.hipaa, .fda, .statePrivacy],
        .europeanUnion: [.gdpr, .mdr, .euPrivacy],
        .turkey: [.kvkk, .tmmda],
        .japanKorea: [.appi, .pmda],
        .middleEast: [.pdpl, .sfda],
        .australia: [.privacy, .tga],
        .southAsia: [.pdpb, .traditionalMedicine],
        .mediterranean: [.customaryLaw, .medicalEthics],
        .africanDescent: [.culturalHeritage, .traditionalPractices]
    ]
    
    private var privacyRequirements: [ComplianceRule: Set<PrivacyRequirement>] = [
        .hipaa: [.encryption, .audit, .authorization, .minimumAccess],
        .gdpr: [.consent, .portability, .erasure, .breach],
        .kvkk: [.explicitConsent, .transfer, .processing],
        .appi: [.notice, .purpose, .security],
        .pdpl: [.collection, .processing, .transfer],
        .privacy: [.notification, .access, .correction],
        .pdpb: [.consent, .processing, .culturalRights],
        .customaryLaw: [.culturalRespect, .communityConsent],
        .culturalHeritage: [.traditionalKnowledge, .culturalOwnership]
    ]
    
    private init() {
        let regionCode = Locale.current.regionCode ?? "US"
        self.currentRegion = Region(rawValue: regionCode) ?? .unitedStates
    }
    
    func getCurrentRegion() -> Region {
        return currentRegion
    }
    
    func setRegion(_ region: Region) throws {
        guard complianceRules[region] != nil else {
            throw ComplianceError.unsupportedRegion(region)
        }
        
        let oldRegion = currentRegion
        currentRegion = region
        
        NotificationCenter.default.post(
            name: .regionDidChange,
            object: nil,
            userInfo: ["region": region, "previousRegion": oldRegion]
        )
    }
    
    func validateCompliance(_ data: PatientData) throws {
        let rules = complianceRules[currentRegion] ?? []
        
        for rule in rules {
            try validateRule(rule, for: data)
        }
    }
    
    func getRequiredConsents() -> Set<ConsentType> {
        switch currentRegion {
        case .unitedStates:
            return [.hipaa, .photography, .dataProcessing]
        case .europeanUnion:
            return [.gdpr, .photography, .dataProcessing, .marketing]
        case .turkey:
            return [.kvkk, .photography, .dataProcessing]
        case .japanKorea:
            return [.appi, .photography, .dataProcessing]
        case .middleEast:
            return [.pdpl, .photography, .dataProcessing, .culturalConsideration]
        case .southAsia:
            return [.dataProcessing, .photography, .culturalConsideration, .religiousConsent]
        case .mediterranean:
            return [.dataProcessing, .photography, .culturalConsideration]
        case .africanDescent:
            return [.dataProcessing, .photography, .culturalConsideration]
        default:
            return [.dataProcessing, .photography]
        }
    }
    
    private func validateRule(_ rule: ComplianceRule, for data: PatientData) throws {
        guard let requirements = privacyRequirements[rule] else { return }
        
        for requirement in requirements {
            switch requirement {
            case .encryption:
                guard data.isEncrypted else {
                    throw ComplianceError.encryptionRequired
                }
            case .audit:
                guard data.hasAuditTrail else {
                    throw ComplianceError.auditTrailRequired
                }
            case .authorization:
                guard data.hasValidAuthorization else {
                    throw ComplianceError.authorizationRequired
                }
            case .consent:
                guard data.hasValidConsent else {
                    throw ComplianceError.consentRequired
                }
            case .culturalRights:
                guard data.hasCulturalRightsAcknowledgment else {
                    throw ComplianceError.culturalRightsRequired
                }
            case .traditionalKnowledge:
                guard data.hasTraditionalKnowledgeProtection else {
                    throw ComplianceError.traditionalKnowledgeProtectionRequired
                }
            default:
                // Handle other requirements
                break
            }
        }
    }
}

// MARK: - Supporting Types

enum Region: String {
    case unitedStates = "US"
    case europeanUnion = "EU"
    case turkey = "TR"
    case japanKorea = "JP"
    case middleEast = "SA"
    case australia = "AU"
    case southAsia = "IN"
    case mediterranean = "MED"
    case africanDescent = "AFR"
}

enum ComplianceRule {
    case hipaa        // US Healthcare
    case gdpr         // EU Data Protection
    case kvkk         // Turkish Data Protection
    case appi         // Japanese Privacy
    case pdpl         // Saudi Privacy
    case privacy      // Australian Privacy
    case pdpb         // Indian Privacy
    case customaryLaw // Mediterranean
    case culturalHeritage // African Heritage
    case fda          // US Medical Device
    case mdr          // EU Medical Device
    case tmmda        // Turkish Medical Device
    case pmda         // Japanese Medical Device
    case sfda         // Saudi Medical Device
    case tga          // Australian Medical Device
    case statePrivacy // US State Privacy Laws
    case euPrivacy    // Additional EU Privacy
    case traditionalMedicine // Traditional Medicine
    case medicalEthics      // Medical Ethics
    case traditionalPractices // Traditional Practices
}

enum PrivacyRequirement {
    case encryption
    case audit
    case authorization
    case minimumAccess
    case consent
    case portability
    case erasure
    case breach
    case explicitConsent
    case transfer
    case processing
    case notice
    case purpose
    case security
    case collection
    case notification
    case access
    case correction
    case culturalRights
    case culturalRespect
    case communityConsent
    case traditionalKnowledge
    case culturalOwnership
}

enum ComplianceError: LocalizedError {
    case unsupportedRegion(Region)
    case encryptionRequired
    case auditTrailRequired
    case authorizationRequired
    case consentRequired
    case culturalRightsRequired
    case traditionalKnowledgeProtectionRequired
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Compliance rules not defined for region: \(region)"
        case .encryptionRequired:
            return "Data encryption is required"
        case .auditTrailRequired:
            return "Audit trail is required"
        case .authorizationRequired:
            return "Valid authorization is required"
        case .consentRequired:
            return "Valid consent is required"
        case .culturalRightsRequired:
            return "Cultural rights acknowledgment is required"
        case .traditionalKnowledgeProtectionRequired:
            return "Traditional knowledge protection is required"
        }
    }
}

extension Notification.Name {
    static let regionDidChange = Notification.Name("regionDidChange")
}