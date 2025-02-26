import Foundation

class TreatmentPlanGenerator {
    static let shared = TreatmentPlanGenerator()
    
    private let analytics = AnalyticsService.shared
    private let regionManager = RegionalComplianceManager.shared
    private let culturalAnalyzer = CulturalPatternAnalyzer.shared
    
    // Regional treatment considerations
    private var treatmentConfigs: [Region: TreatmentConfig] = [
        .unitedStates: .init(
            standardApproaches: [.fue, .fut],
            minDensity: 35,  // grafts per cm²
            maxSessionDuration: 8,  // hours
            recoveryPeriod: 14,    // days
            followupSchedule: [7, 14, 30, 90, 180]  // days
        ),
        .europeanUnion: .init(
            standardApproaches: [.fue, .fut],
            minDensity: 40,
            maxSessionDuration: 7,
            recoveryPeriod: 14,
            followupSchedule: [7, 14, 30, 90, 180]
        ),
        .southAsia: .init(
            standardApproaches: [.fue],
            minDensity: 38,
            maxSessionDuration: 6,
            recoveryPeriod: 21,
            followupSchedule: [7, 14, 30, 90, 180],
            culturalConsiderations: [
                .religiousScheduling,
                .traditionalMedicine,
                .familyInvolvement,
                .dietaryRestrictions
            ]
        ),
        .mediterranean: .init(
            standardApproaches: [.fue],
            minDensity: 38,
            maxSessionDuration: 7,
            recoveryPeriod: 14,
            followupSchedule: [7, 14, 30, 90, 180],
            culturalConsiderations: [
                .religiousScheduling,
                .familyInvolvement,
                .traditionalPractices
            ]
        ),
        .africanDescent: .init(
            standardApproaches: [.fue],
            minDensity: 32,
            maxSessionDuration: 8,
            recoveryPeriod: 21,
            followupSchedule: [7, 14, 30, 90, 180],
            culturalConsiderations: [
                .hairTexture,
                .traditionalPractices,
                .communitySupport
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func generateTreatmentPlan(
        for patient: PatientProfile,
        analysis: CulturalAnalysisResult
    ) async throws -> TreatmentPlan {
        let region = regionManager.getCurrentRegion()
        guard let config = treatmentConfigs[region] else {
            throw TreatmentError.unsupportedRegion(region)
        }
        
        // Apply cultural analysis
        let culturalFactors = extractCulturalFactors(
            from: analysis,
            config: config
        )
        
        // Calculate core treatment parameters
        let parameters = try calculateTreatmentParameters(
            patient: patient,
            cultural: culturalFactors,
            config: config
        )
        
        // Generate schedule
        let schedule = try generateTreatmentSchedule(
            parameters: parameters,
            cultural: culturalFactors,
            config: config
        )
        
        // Generate instructions
        let instructions = try generateInstructions(
            parameters: parameters,
            cultural: culturalFactors,
            config: config
        )
        
        let plan = TreatmentPlan(
            patientId: patient.id,
            parameters: parameters,
            schedule: schedule,
            instructions: instructions,
            culturalConsiderations: culturalFactors,
            createdAt: Date()
        )
        
        // Track plan generation
        trackPlanGeneration(plan, region: region)
        
        return plan
    }
    
    func validateTreatmentPlan(_ plan: TreatmentPlan) throws {
        let region = regionManager.getCurrentRegion()
        guard let config = treatmentConfigs[region] else {
            throw TreatmentError.unsupportedRegion(region)
        }
        
        // Validate core parameters
        try validateParameters(
            plan.parameters,
            config: config
        )
        
        // Validate cultural considerations
        if let considerations = config.culturalConsiderations {
            try validateCulturalConsiderations(
                plan.culturalConsiderations,
                required: considerations
            )
        }
        
        // Validate schedule
        try validateSchedule(
            plan.schedule,
            config: config
        )
        
        // Validate instructions
        try validateInstructions(
            plan.instructions,
            cultural: plan.culturalConsiderations,
            config: config
        )
    }
    
    func updateTreatmentPlan(
        _ plan: TreatmentPlan,
        with feedback: PatientFeedback
    ) async throws -> TreatmentPlan {
        var updatedPlan = plan
        
        // Analyze feedback for cultural context
        let culturalContext = try await analyzeFeedbackContext(feedback)
        
        // Update parameters if needed
        if let parameterAdjustments = calculateParameterAdjustments(
            from: feedback,
            context: culturalContext
        ) {
            updatedPlan.parameters = try adjustParameters(
                plan.parameters,
                with: parameterAdjustments
            )
        }
        
        // Update schedule if needed
        if let scheduleAdjustments = calculateScheduleAdjustments(
            from: feedback,
            context: culturalContext
        ) {
            updatedPlan.schedule = try adjustSchedule(
                plan.schedule,
                with: scheduleAdjustments
            )
        }
        
        // Update cultural considerations
        updatedPlan.culturalConsiderations.merge(
            culturalContext.newConsiderations
        )
        
        // Track plan update
        trackPlanUpdate(updatedPlan, feedback: feedback)
        
        return updatedPlan
    }
    
    // MARK: - Private Methods
    
    private func extractCulturalFactors(
        from analysis: CulturalAnalysisResult,
        config: TreatmentConfig
    ) -> CulturalFactors {
        var factors = CulturalFactors()
        
        // Extract religious considerations
        factors.religiousFactors = analysis.religiousConsiderations
            .map { ReligiousFactor(religion: $0) }
        
        // Extract traditional practices
        factors.traditionalPractices = analysis.recommendations
            .filter { $0.type == .traditionalStyle }
            .map { TreatmentPractice(description: $0.description) }
        
        // Add regional cultural considerations
        if let considerations = config.culturalConsiderations {
            factors.culturalConsiderations = considerations
        }
        
        return factors
    }
    
    private func calculateTreatmentParameters(
        patient: PatientProfile,
        cultural: CulturalFactors,
        config: TreatmentConfig
    ) throws -> TreatmentParameters {
        var parameters = TreatmentParameters()
        
        // Calculate base parameters
        parameters.approach = selectTreatmentApproach(
            for: patient,
            config: config
        )
        
        parameters.density = calculateTargetDensity(
            for: patient,
            minimum: config.minDensity
        )
        
        // Adjust for cultural factors
        parameters.sessionDuration = adjustSessionDuration(
            config.maxSessionDuration,
            cultural: cultural
        )
        
        parameters.recoveryPeriod = adjustRecoveryPeriod(
            config.recoveryPeriod,
            cultural: cultural
        )
        
        return parameters
    }
    
    private func generateTreatmentSchedule(
        parameters: TreatmentParameters,
        cultural: CulturalFactors,
        config: TreatmentConfig
    ) throws -> TreatmentSchedule {
        var schedule = TreatmentSchedule()
        
        // Set base follow-up schedule
        schedule.followupDays = config.followupSchedule
        
        // Adjust for religious factors
        if let religious = cultural.religiousFactors {
            schedule.restrictedDates = calculateRestrictedDates(
                for: religious
            )
        }
        
        // Adjust for traditional practices
        if let practices = cultural.traditionalPractices {
            schedule.specialConsiderations = extractScheduleConsiderations(
                from: practices
            )
        }
        
        return schedule
    }
    
    private func generateInstructions(
        parameters: TreatmentParameters,
        cultural: CulturalFactors,
        config: TreatmentConfig
    ) throws -> TreatmentInstructions {
        var instructions = TreatmentInstructions()
        
        // Generate base instructions
        instructions.pretreatment = generatePretreatmentInstructions(
            parameters,
            cultural: cultural
        )
        
        instructions.posttreatment = generatePosttreatmentInstructions(
            parameters,
            cultural: cultural
        )
        
        // Add cultural-specific instructions
        if let considerations = cultural.culturalConsiderations {
            instructions.culturalGuidelines = generateCulturalGuidelines(
                considerations
            )
        }
        
        return instructions
    }
    
    private func trackPlanGeneration(_ plan: TreatmentPlan, region: Region) {
        analytics.trackEvent(
            category: .treatment,
            action: "plan_generation",
            label: region.rawValue,
            value: 1,
            metadata: [
                "patient_id": plan.patientId.uuidString,
                "approach": plan.parameters.approach.rawValue,
                "density": String(plan.parameters.density),
                "cultural_factors": String(plan.culturalConsiderations.count)
            ]
        )
    }
}

// MARK: - Supporting Types

struct TreatmentConfig {
    let standardApproaches: Set<TreatmentApproach>
    let minDensity: Float
    let maxSessionDuration: Int
    let recoveryPeriod: Int
    let followupSchedule: [Int]
    let culturalConsiderations: Set<CulturalConsideration>?
}

struct TreatmentPlan {
    let patientId: UUID
    var parameters: TreatmentParameters
    var schedule: TreatmentSchedule
    var instructions: TreatmentInstructions
    var culturalConsiderations: CulturalFactors
    let createdAt: Date
}

struct TreatmentParameters {
    var approach: TreatmentApproach
    var density: Float
    var sessionDuration: Int
    var recoveryPeriod: Int
    var specialRequirements: Set<Requirement>?
    
    enum Requirement {
        case dietaryRestriction(String)
        case activityRestriction(String)
        case culturalPractice(String)
    }
}

struct TreatmentSchedule {
    var followupDays: [Int]
    var restrictedDates: Set<DateInterval>?
    var specialConsiderations: [String]?
}

struct TreatmentInstructions {
    var pretreatment: [Instruction]
    var posttreatment: [Instruction]
    var culturalGuidelines: [Guideline]?
    
    struct Instruction {
        let step: Int
        let description: String
        let importance: Importance
        let culturalContext: String?
    }
    
    struct Guideline {
        let title: String
        let description: String
        let importance: Importance
    }
    
    enum Importance {
        case critical
        case high
        case medium
        case optional
    }
}

struct CulturalFactors {
    var religiousFactors: [ReligiousFactor]?
    var traditionalPractices: [TreatmentPractice]?
    var culturalConsiderations: Set<CulturalConsideration>?
    
    mutating func merge(_ considerations: Set<CulturalConsideration>) {
        if self.culturalConsiderations == nil {
            self.culturalConsiderations = considerations
        } else {
            self.culturalConsiderations?.formUnion(considerations)
        }
    }
}

struct ReligiousFactor {
    let religion: Religion
    let restrictions: Set<Restriction>?
    
    enum Restriction {
        case dietary(String)
        case schedule(DateInterval)
        case practice(String)
    }
}

struct TreatmentPractice {
    let description: String
    let timing: PracticeTiming?
    let requirements: Set<Requirement>?
    
    enum PracticeTiming {
        case before(days: Int)
        case after(days: Int)
        case during
    }
    
    enum Requirement {
        case materials(Set<String>)
        case assistance(String)
        case environment(String)
    }
}

enum TreatmentApproach: String {
    case fue = "FUE"
    case fut = "FUT"
}

enum TreatmentError: LocalizedError {
    case unsupportedRegion(Region)
    case invalidParameters(String)
    case schedulingConflict(String)
    case culturalConflict(String)
    case instructionConflict(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Treatment planning not supported for region: \(region)"
        case .invalidParameters(let reason):
            return "Invalid treatment parameters: \(reason)"
        case .schedulingConflict(let reason):
            return "Treatment scheduling conflict: \(reason)"
        case .culturalConflict(let reason):
            return "Cultural consideration conflict: \(reason)"
        case .instructionConflict(let reason):
            return "Treatment instruction conflict: \(reason)"
        }
    }
}