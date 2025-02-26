import Foundation
import CryptoKit

struct PatientData: Codable {
    let id: UUID
    let personalInfo: PersonalInfo
    let medicalRecords: [MedicalRecord]
    let consents: Set<ConsentRecord>
    let culturalProfile: CulturalProfile?
    let securityInfo: SecurityInfo
    let auditTrail: [AuditEvent]
    
    var isEncrypted: Bool {
        securityInfo.encryptionStatus == .encrypted
    }
    
    var hasAuditTrail: Bool {
        !auditTrail.isEmpty
    }
    
    var hasValidAuthorization: Bool {
        guard let latestAuth = securityInfo.authorizations.max(by: { $0.timestamp < $1.timestamp }) else {
            return false
        }
        return latestAuth.isValid && !latestAuth.isExpired
    }
    
    var hasValidConsent: Bool {
        let requiredConsents = RegionalComplianceManager.shared.getRequiredConsents()
        let activeConsents = consents.filter { !$0.isExpired && $0.isValid }
        return requiredConsents.allSatisfy { required in
            activeConsents.contains { $0.type == required }
        }
    }
    
    var hasCulturalRightsAcknowledgment: Bool {
        culturalProfile?.rightsAcknowledged ?? false
    }
    
    var hasTraditionalKnowledgeProtection: Bool {
        culturalProfile?.traditionalKnowledgeProtected ?? false
    }
}

struct PersonalInfo: Codable {
    let firstName: String
    let lastName: String
    let dateOfBirth: Date
    let gender: Gender
    let contactInfo: ContactInfo
    let culturalBackground: String?
    let preferredLanguage: String
    let religiousConsiderations: String?
}

struct ContactInfo: Codable {
    let email: String
    let phone: String
    let address: Address
    let preferredContactMethod: ContactMethod
    
    enum ContactMethod: String, Codable {
        case email
        case phone
        case sms
    }
}

struct Address: Codable {
    let street: String
    let city: String
    let state: String?
    let postalCode: String
    let country: String
}

struct MedicalRecord: Codable {
    let id: UUID
    let date: Date
    let type: RecordType
    let data: RecordData
    let provider: ProviderInfo
    let attachments: [Attachment]
    
    enum RecordType: String, Codable {
        case consultation
        case treatment
        case followUp
        case scan
        case analysis
    }
}

struct RecordData: Codable {
    let diagnosis: String?
    let treatment: String?
    let notes: String?
    let measurements: [String: Double]?
    let recommendations: [String]?
}

struct ProviderInfo: Codable {
    let id: UUID
    let name: String
    let specialization: String
    let license: String
}

struct Attachment: Codable {
    let id: UUID
    let type: AttachmentType
    let url: URL
    let mimeType: String
    let hash: String
    
    enum AttachmentType: String, Codable {
        case photo
        case scan
        case document
        case video
    }
}

struct ConsentRecord: Codable {
    let id: UUID
    let type: ConsentType
    let timestamp: Date
    let expirationDate: Date?
    let signature: String
    let witnessed: Bool
    let documentUrl: URL?
    
    var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }
    
    var isValid: Bool {
        witnessed && !signature.isEmpty
    }
}

struct CulturalProfile: Codable {
    let region: Region
    let culturalBackground: String
    let religiousAffiliation: String?
    let traditionalPractices: [String]?
    let culturalPreferences: [String: String]
    let rightsAcknowledged: Bool
    let traditionalKnowledgeProtected: Bool
    let lastUpdated: Date
}

struct SecurityInfo: Codable {
    let encryptionStatus: EncryptionStatus
    let authorizations: [Authorization]
    let accessLevel: AccessLevel
    let lastSecurityReview: Date
    
    enum EncryptionStatus: String, Codable {
        case encrypted
        case decrypted
        case partiallyEncrypted
    }
    
    enum AccessLevel: String, Codable {
        case full
        case partial
        case restricted
    }
}

struct Authorization: Codable {
    let id: UUID
    let type: AuthorizationType
    let timestamp: Date
    let expirationDate: Date
    let grantedBy: UUID
    let scope: Set<AuthScope>
    
    var isExpired: Bool {
        Date() > expirationDate
    }
    
    var isValid: Bool {
        !isExpired && !scope.isEmpty
    }
    
    enum AuthorizationType: String, Codable {
        case treatment
        case research
        case billing
        case administrative
    }
    
    enum AuthScope: String, Codable {
        case read
        case write
        case delete
        case share
    }
}

struct AuditEvent: Codable {
    let id: UUID
    let timestamp: Date
    let action: AuditAction
    let userId: UUID
    let userRole: String
    let resourceId: UUID
    let resourceType: String
    let details: String
    
    enum AuditAction: String, Codable {
        case view
        case create
        case update
        case delete
        case share
        case export
        case print
    }
}

enum Gender: String, Codable {
    case male
    case female
    case other
    case preferNotToSay
}