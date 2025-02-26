import Foundation

class CommunicationStyleManager {
    static let shared = CommunicationStyleManager()
    
    private let regionManager = RegionalComplianceManager.shared
    private let languageFormatter = LanguageStyleFormatter.shared
    private let analytics = AnalyticsService.shared
    
    // Regional communication styles
    private var communicationConfigs: [Region: CommunicationConfig] = [
        .unitedStates: .init(
            formalityLevel: .moderate,
            familyInvolvement: .optional,
            decisionMaking: .individual,
            communicationStyle: .direct,
            nonverbalCues: [.eyeContact, .personalSpace],
            topics: [
                .avoid: ["age", "weight", "financial_status"],
                .careful: ["medical_history", "lifestyle_choices"],
                .encourage: ["treatment_goals", "expectations"]
            ]
        ),
        .europeanUnion: .init(
            formalityLevel: .high,
            familyInvolvement: .recommended,
            decisionMaking: .individual,
            communicationStyle: .structured,
            nonverbalCues: [.eyeContact, .personalSpace, .formalPosture],
            topics: [
                .avoid: ["personal_life", "financial_status"],
                .careful: ["medical_history", "age"],
                .encourage: ["treatment_process", "scientific_evidence"]
            ]
        ),
        .southAsia: .init(
            formalityLevel: .veryHigh,
            familyInvolvement: .expected,
            decisionMaking: .familyBased,
            communicationStyle: .indirect,
            nonverbalCues: [.limitedEyeContact, .respectfulDistance],
            topics: [
                .avoid: ["personal_issues", "direct_criticism"],
                .careful: ["cost", "treatment_timeline"],
                .encourage: ["family_support", "cultural_values"]
            ],
            culturalConsiderations: [
                .ageHierarchy,
                .genderDynamics,
                .religiousValues
            ]
        ),
        .mediterranean: .init(
            formalityLevel: .high,
            familyInvolvement: .expected,
            decisionMaking: .familyBased,
            communicationStyle: .expressive,
            nonverbalCues: [.expressiveGestures, .closeProximity],
            topics: [
                .avoid: ["personal_failures", "negative_outcomes"],
                .careful: ["cost", "timeline"],
                .encourage: ["family_involvement", "long_term_benefits"]
            ],
            culturalConsiderations: [
                .familyHonor,
                .genderRoles,
                .communityStatus
            ]
        ),
        .africanDescent: .init(
            formalityLevel: .high,
            familyInvolvement: .encouraged,
            decisionMaking: .communityInfluenced,
            communicationStyle: .respectful,
            nonverbalCues: [.respectfulGaze, .personalSpace],
            topics: [
                .avoid: ["stereotypes", "assumptions"],
                .careful: ["genetic_factors", "cultural_practices"],
                .encourage: ["community_support", "cultural_identity"]
            ],
            culturalConsiderations: [
                .communityValues,
                .culturalIdentity,
                .historicalContext
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func formatMessage(
        _ message: CommunicationMessage,
        for recipient: RecipientProfile
    ) async throws -> CommunicationMessage {
        let region = regionManager.getCurrentRegion()
        guard let config = communicationConfigs[region] else {
            throw CommunicationError.unsupportedRegion(region)
        }
        
        // Apply cultural considerations
        var formattedMessage = try applyCulturalConsiderations(
            message,
            for: recipient,
            config: config
        )
        
        // Adjust formality
        formattedMessage = try adjustFormality(
            formattedMessage,
            level: config.formalityLevel,
            recipient: recipient
        )
        
        // Apply communication style
        formattedMessage = applyStyleGuidelines(
            formattedMessage,
            style: config.communicationStyle,
            config: config
        )
        
        // Validate content
        try validateMessageContent(
            formattedMessage,
            topics: config.topics,
            cultural: config.culturalConsiderations
        )
        
        // Track formatting
        trackMessageFormatting(
            original: message,
            formatted: formattedMessage,
            recipient: recipient
        )
        
        return formattedMessage
    }
    
    func validateCommunicationStyle(
        _ interaction: CommunicationInteraction
    ) throws {
        let region = regionManager.getCurrentRegion()
        guard let config = communicationConfigs[region] else {
            throw CommunicationError.unsupportedRegion(region)
        }
        
        // Validate formality
        try validateFormality(
            interaction,
            required: config.formalityLevel
        )
        
        // Validate family involvement
        try validateFamilyInvolvement(
            interaction,
            required: config.familyInvolvement
        )
        
        // Validate decision-making approach
        try validateDecisionMaking(
            interaction,
            approach: config.decisionMaking
        )
        
        // Validate cultural considerations
        if let considerations = config.culturalConsiderations {
            try validateCulturalConsiderations(
                interaction,
                required: considerations
            )
        }
    }
    
    func suggestCommunicationApproach(
        for scenario: CommunicationScenario
    ) -> CommunicationApproach {
        let region = regionManager.getCurrentRegion()
        guard let config = communicationConfigs[region] else {
            return .default
        }
        
        var approach = CommunicationApproach()
        
        // Set base style
        approach.style = config.communicationStyle
        
        // Add nonverbal guidance
        approach.nonverbalGuidance = generateNonverbalGuidance(
            config.nonverbalCues,
            scenario: scenario
        )
        
        // Add topic recommendations
        approach.recommendedTopics = config.topics[.encourage] ?? []
        approach.topicsToAvoid = config.topics[.avoid] ?? []
        
        // Add cultural adjustments
        if let considerations = config.culturalConsiderations {
            approach.culturalAdjustments = generateCulturalAdjustments(
                considerations,
                scenario: scenario
            )
        }
        
        return approach
    }
    
    // MARK: - Private Methods
    
    private func applyCulturalConsiderations(
        _ message: CommunicationMessage,
        for recipient: RecipientProfile,
        config: CommunicationConfig
    ) throws -> CommunicationMessage {
        var formatted = message
        
        // Apply language formatting
        formatted.content = try languageFormatter.formatText(
            message.content,
            context: .init(
                identifier: "communication",
                type: .consultation,
                userData: recipient.culturalContext
            )
        )
        
        // Adjust for family involvement
        if config.familyInvolvement != .optional {
            formatted = includeFamilyContext(formatted, recipient: recipient)
        }
        
        // Apply cultural adjustments
        if let considerations = config.culturalConsiderations {
            formatted = applyCulturalAdjustments(
                formatted,
                considerations: considerations,
                recipient: recipient
            )
        }
        
        return formatted
    }
    
    private func validateMessageContent(
        _ message: CommunicationMessage,
        topics: TopicGuidelines,
        cultural: Set<CulturalConsideration>?
    ) throws {
        // Check for avoided topics
        if let avoided = topics[.avoid],
           containsAvoidedTopics(message.content, topics: avoided) {
            throw CommunicationError.containsAvoidedTopics
        }
        
        // Validate careful topics
        if let careful = topics[.careful] {
            try validateCarefulTopics(
                message.content,
                topics: careful
            )
        }
        
        // Validate cultural sensitivity
        if let cultural = cultural {
            try validateCulturalSensitivity(
                message.content,
                considerations: cultural
            )
        }
    }
    
    private func trackMessageFormatting(
        original: CommunicationMessage,
        formatted: CommunicationMessage,
        recipient: RecipientProfile
    ) {
        analytics.trackEvent(
            category: .communication,
            action: "message_formatting",
            label: recipient.region.rawValue,
            value: 1,
            metadata: [
                "original_length": String(original.content.count),
                "formatted_length": String(formatted.content.count),
                "cultural_context": recipient.culturalContext.keys.joined(separator: ",")
            ]
        )
    }
}

// MARK: - Supporting Types

struct CommunicationConfig {
    let formalityLevel: FormalityLevel
    let familyInvolvement: FamilyInvolvement
    let decisionMaking: DecisionMakingStyle
    let communicationStyle: CommunicationStyle
    let nonverbalCues: Set<NonverbalCue>
    let topics: TopicGuidelines
    let culturalConsiderations: Set<CulturalConsideration>?
}

struct CommunicationMessage {
    let id: UUID
    var content: String
    let context: MessageContext
    var metadata: [String: Any]
    
    struct MessageContext {
        let type: MessageType
        let urgency: MessageUrgency
        let sensitivity: MessageSensitivity
    }
    
    enum MessageType {
        case consultation
        case followup
        case instruction
        case reminder
    }
    
    enum MessageUrgency {
        case routine
        case important
        case urgent
    }
    
    enum MessageSensitivity {
        case normal
        case sensitive
        case highlySensitive
    }
}

struct CommunicationApproach {
    var style: CommunicationStyle
    var nonverbalGuidance: [NonverbalGuidance]
    var recommendedTopics: [String]
    var topicsToAvoid: [String]
    var culturalAdjustments: [CulturalAdjustment]
    
    static let `default` = CommunicationApproach(
        style: .direct,
        nonverbalGuidance: [],
        recommendedTopics: [],
        topicsToAvoid: [],
        culturalAdjustments: []
    )
}

enum FamilyInvolvement {
    case optional
    case recommended
    case encouraged
    case expected
}

enum DecisionMakingStyle {
    case individual
    case familyBased
    case communityInfluenced
}

enum CommunicationStyle {
    case direct
    case indirect
    case structured
    case expressive
    case respectful
}

enum NonverbalCue {
    case eyeContact
    case limitedEyeContact
    case personalSpace
    case closeProximity
    case respectfulGaze
    case expressiveGestures
    case formalPosture
    case respectfulDistance
}

typealias TopicGuidelines = [TopicCategory: [String]]

enum TopicCategory {
    case avoid
    case careful
    case encourage
}

struct NonverbalGuidance {
    let cue: NonverbalCue
    let description: String
    let importance: Importance
    
    enum Importance {
        case critical
        case recommended
        case optional
    }
}

struct CulturalAdjustment {
    let consideration: CulturalConsideration
    let adjustment: String
    let rationale: String
}

enum CommunicationError: LocalizedError {
    case unsupportedRegion(Region)
    case invalidFormality(required: FormalityLevel)
    case insufficientFamilyInvolvement
    case inappropriateDecisionMaking
    case containsAvoidedTopics
    case culturallyInsensitive(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Communication style not configured for region: \(region)"
        case .invalidFormality(let required):
            return "Invalid formality level, required: \(required)"
        case .insufficientFamilyInvolvement:
            return "Insufficient family involvement in communication"
        case .inappropriateDecisionMaking:
            return "Inappropriate decision-making approach"
        case .containsAvoidedTopics:
            return "Communication contains avoided topics"
        case .culturallyInsensitive(let reason):
            return "Culturally insensitive communication: \(reason)"
        }
    }
}