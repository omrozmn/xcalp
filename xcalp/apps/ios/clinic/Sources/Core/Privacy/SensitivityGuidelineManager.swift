import Foundation

class SensitivityGuidelineManager {
    static let shared = SensitivityGuidelineManager()
    
    private let regionManager = RegionalComplianceManager.shared
    private let analytics = AnalyticsService.shared
    private let keychain = KeychainManager.shared
    
    // Regional sensitivity configurations
    private var sensitivityConfigs: [Region: SensitivityConfig] = [
        .unitedStates: .init(
            dataCategories: [
                .medical: .high,
                .personal: .medium,
                .demographic: .low
            ],
            retentionPeriods: [
                .medical: 2190,      // 6 years
                .personal: 730,      // 2 years
                .demographic: 1825   // 5 years
            ],
            accessControls: [
                .medical: [.physician, .nurse],
                .personal: [.physician, .nurse, .staff],
                .demographic: [.physician, .nurse, .staff, .admin]
            ],
            encryptionRequirements: [
                .medical: .aes256,
                .personal: .aes256,
                .demographic: .aes128
            ]
        ),
        .europeanUnion: .init(
            dataCategories: [
                .medical: .high,
                .personal: .high,
                .demographic: .medium
            ],
            retentionPeriods: [
                .medical: 3650,      // 10 years
                .personal: 365,      // 1 year
                .demographic: 730    // 2 years
            ],
            accessControls: [
                .medical: [.physician],
                .personal: [.physician, .nurse],
                .demographic: [.physician, .nurse, .staff]
            ],
            encryptionRequirements: [
                .medical: .aes256,
                .personal: .aes256,
                .demographic: .aes256
            ],
            dataMinimization: true,
            rightToBeForgotten: true
        ),
        .southAsia: .init(
            dataCategories: [
                .medical: .high,
                .personal: .high,
                .demographic: .medium,
                .cultural: .high,
                .religious: .critical
            ],
            retentionPeriods: [
                .medical: 1825,      // 5 years
                .personal: 730,      // 2 years
                .demographic: 1095,  // 3 years
                .cultural: 1825,     // 5 years
                .religious: 1825     // 5 years
            ],
            accessControls: [
                .medical: [.physician],
                .personal: [.physician, .nurse],
                .demographic: [.physician, .nurse, .staff],
                .cultural: [.physician, .culturalAdvisor],
                .religious: [.physician, .religiousAdvisor]
            ],
            encryptionRequirements: [
                .medical: .aes256,
                .personal: .aes256,
                .demographic: .aes256,
                .cultural: .aes256,
                .religious: .aes256
            ],
            culturalConsiderations: [
                .familyPrivacy,
                .religiousConfidentiality,
                .communityRespect
            ]
        ),
        .mediterranean: .init(
            dataCategories: [
                .medical: .high,
                .personal: .high,
                .demographic: .medium,
                .cultural: .high,
                .religious: .critical
            ],
            retentionPeriods: [
                .medical: 1825,      // 5 years
                .personal: 730,      // 2 years
                .demographic: 1095,  // 3 years
                .cultural: 1825,     // 5 years
                .religious: 1825     // 5 years
            ],
            accessControls: [
                .medical: [.physician],
                .personal: [.physician, .nurse],
                .demographic: [.physician, .nurse, .staff],
                .cultural: [.physician, .culturalAdvisor],
                .religious: [.physician, .religiousAdvisor]
            ],
            encryptionRequirements: [
                .medical: .aes256,
                .personal: .aes256,
                .demographic: .aes256,
                .cultural: .aes256,
                .religious: .aes256
            ],
            culturalConsiderations: [
                .familyPrivacy,
                .religiousConfidentiality
            ]
        ),
        .africanDescent: .init(
            dataCategories: [
                .medical: .high,
                .personal: .high,
                .demographic: .medium,
                .cultural: .critical,
                .traditional: .critical
            ],
            retentionPeriods: [
                .medical: 1825,      // 5 years
                .personal: 730,      // 2 years
                .demographic: 1095,  // 3 years
                .cultural: 1825,     // 5 years
                .traditional: 1825   // 5 years
            ],
            accessControls: [
                .medical: [.physician],
                .personal: [.physician, .nurse],
                .demographic: [.physician, .nurse, .staff],
                .cultural: [.physician, .culturalAdvisor],
                .traditional: [.physician, .traditionalHealer]
            ],
            encryptionRequirements: [
                .medical: .aes256,
                .personal: .aes256,
                .demographic: .aes256,
                .cultural: .aes256,
                .traditional: .aes256
            ],
            culturalConsiderations: [
                .communityPrivacy,
                .traditionalKnowledge,
                .culturalHeritage
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func validateDataSensitivity(
        _ data: SensitiveData
    ) throws {
        let region = regionManager.getCurrentRegion()
        guard let config = sensitivityConfigs[region] else {
            throw SensitivityError.unsupportedRegion(region)
        }
        
        // Validate sensitivity level
        try validateSensitivityLevel(
            data,
            categories: config.dataCategories
        )
        
        // Validate retention period
        try validateRetentionPeriod(
            data,
            periods: config.retentionPeriods
        )
        
        // Validate access controls
        try validateAccessControls(
            data,
            controls: config.accessControls
        )
        
        // Validate encryption
        try validateEncryption(
            data,
            requirements: config.encryptionRequirements
        )
        
        // Validate cultural considerations if applicable
        if let considerations = config.culturalConsiderations {
            try validateCulturalConsiderations(
                data,
                required: considerations
            )
        }
        
        // Validate data minimization if required
        if config.dataMinimization == true {
            try validateDataMinimization(data)
        }
    }
    
    func getHandlingGuidelines(
        for category: DataCategory,
        context: DataContext
    ) throws -> SensitivityGuidelines {
        let region = regionManager.getCurrentRegion()
        guard let config = sensitivityConfigs[region] else {
            throw SensitivityError.unsupportedRegion(region)
        }
        
        // Get base guidelines
        var guidelines = try generateBaseGuidelines(
            category: category,
            config: config
        )
        
        // Add cultural guidelines if applicable
        if let considerations = config.culturalConsiderations {
            let culturalGuidelines = generateCulturalGuidelines(
                category: category,
                considerations: considerations,
                context: context
            )
            guidelines.culturalGuidelines = culturalGuidelines
        }
        
        return guidelines
    }
    
    func maskSensitiveData(
        _ data: SensitiveData,
        for role: AccessRole
    ) throws -> SensitiveData {
        let region = regionManager.getCurrentRegion()
        guard let config = sensitivityConfigs[region] else {
            throw SensitivityError.unsupportedRegion(region)
        }
        
        var maskedData = data
        
        // Apply role-based masking
        for (category, allowedRoles) in config.accessControls {
            if !allowedRoles.contains(role) {
                maskedData = maskCategory(maskedData, category: category)
            }
        }
        
        // Apply cultural masking if applicable
        if let considerations = config.culturalConsiderations {
            maskedData = applyCulturalMasking(
                maskedData,
                considerations: considerations,
                role: role
            )
        }
        
        return maskedData
    }
    
    // MARK: - Private Methods
    
    private func validateSensitivityLevel(
        _ data: SensitiveData,
        categories: [DataCategory: SensitivityLevel]
    ) throws {
        for (category, level) in categories {
            if data.hasCategory(category) &&
                data.sensitivityLevel(for: category) < level {
                throw SensitivityError.insufficientSensitivityLevel(
                    category: category,
                    required: level,
                    actual: data.sensitivityLevel(for: category)
                )
            }
        }
    }
    
    private func validateRetentionPeriod(
        _ data: SensitiveData,
        periods: [DataCategory: Int]
    ) throws {
        for (category, period) in periods {
            if data.hasCategory(category) {
                let age = Calendar.current.dateComponents(
                    [.day],
                    from: data.creationDate,
                    to: Date()
                ).day ?? 0
                
                if age > period {
                    throw SensitivityError.retentionPeriodExceeded(
                        category: category,
                        daysExceeded: age - period
                    )
                }
            }
        }
    }
    
    private func validateAccessControls(
        _ data: SensitiveData,
        controls: [DataCategory: Set<AccessRole>]
    ) throws {
        let currentRole = try getCurrentUserRole()
        
        for (category, allowedRoles) in controls {
            if data.hasCategory(category) &&
                !allowedRoles.contains(currentRole) {
                throw SensitivityError.unauthorizedAccess(
                    category: category,
                    role: currentRole
                )
            }
        }
    }
    
    private func validateCulturalConsiderations(
        _ data: SensitiveData,
        required: Set<CulturalConsideration>
    ) throws {
        for consideration in required {
            switch consideration {
            case .familyPrivacy:
                try validateFamilyPrivacy(data)
            case .religiousConfidentiality:
                try validateReligiousConfidentiality(data)
            case .communityPrivacy:
                try validateCommunityPrivacy(data)
            case .traditionalKnowledge:
                try validateTraditionalKnowledge(data)
            case .culturalHeritage:
                try validateCulturalHeritage(data)
            case .communityRespect:
                try validateCommunityRespect(data)
            }
        }
    }
    
    private func trackSensitivityValidation(
        _ data: SensitiveData,
        result: Result<Void, Error>
    ) {
        analytics.trackEvent(
            category: .privacy,
            action: "sensitivity_validation",
            label: data.primaryCategory.rawValue,
            value: result.isSuccess ? 1 : 0,
            metadata: [
                "categories": data.categories.map { $0.rawValue }.joined(separator: ","),
                "result": String(describing: result)
            ]
        )
    }
}

// MARK: - Supporting Types

struct SensitivityConfig {
    let dataCategories: [DataCategory: SensitivityLevel]
    let retentionPeriods: [DataCategory: Int]
    let accessControls: [DataCategory: Set<AccessRole>]
    let encryptionRequirements: [DataCategory: EncryptionLevel]
    let culturalConsiderations: Set<CulturalConsideration>?
    let dataMinimization: Bool?
    let rightToBeForgotten: Bool?
}

struct SensitivityGuidelines {
    let accessRestrictions: [AccessRole: Set<Permission>]
    let retentionPolicy: RetentionPolicy
    let encryptionRequirements: [DataCategory: EncryptionLevel]
    var culturalGuidelines: [CulturalGuideline]?
}

enum DataCategory: String {
    case medical
    case personal
    case demographic
    case cultural
    case religious
    case traditional
}

enum SensitivityLevel: Int, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: SensitivityLevel, rhs: SensitivityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum AccessRole {
    case physician
    case nurse
    case staff
    case admin
    case culturalAdvisor
    case religiousAdvisor
    case traditionalHealer
}

enum EncryptionLevel {
    case aes128
    case aes256
}

enum CulturalConsideration {
    case familyPrivacy
    case religiousConfidentiality
    case communityPrivacy
    case traditionalKnowledge
    case culturalHeritage
    case communityRespect
}

struct DataContext {
    let purpose: Purpose
    let audience: Set<AccessRole>
    let culturalContext: [String: Any]
    
    enum Purpose {
        case treatment
        case research
        case administrative
        case cultural
    }
}

enum SensitivityError: LocalizedError {
    case unsupportedRegion(Region)
    case insufficientSensitivityLevel(category: DataCategory, required: SensitivityLevel, actual: SensitivityLevel)
    case retentionPeriodExceeded(category: DataCategory, daysExceeded: Int)
    case unauthorizedAccess(category: DataCategory, role: AccessRole)
    case encryptionRequired(category: DataCategory, required: EncryptionLevel)
    case culturalViolation(consideration: CulturalConsideration, reason: String)
    case dataMinimizationRequired
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Sensitivity guidelines not configured for region: \(region)"
        case .insufficientSensitivityLevel(let category, let required, let actual):
            return "Insufficient sensitivity level for \(category): required \(required), actual \(actual)"
        case .retentionPeriodExceeded(let category, let days):
            return "Retention period exceeded for \(category) by \(days) days"
        case .unauthorizedAccess(let category, let role):
            return "Unauthorized access to \(category) data by role: \(role)"
        case .encryptionRequired(let category, let level):
            return "\(level) encryption required for \(category) data"
        case .culturalViolation(let consideration, let reason):
            return "Cultural consideration violation (\(consideration)): \(reason)"
        case .dataMinimizationRequired:
            return "Data minimization required by regional policy"
        }
    }
}