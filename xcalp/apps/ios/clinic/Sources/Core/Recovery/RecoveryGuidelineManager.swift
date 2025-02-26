import Foundation

class RecoveryGuidelineManager {
    static let shared = RecoveryGuidelineManager()
    
    private let analytics = AnalyticsService.shared
    private let regionManager = RegionalComplianceManager.shared
    private let communicationManager = CommunicationStyleManager.shared
    
    // Regional recovery configurations
    private var recoveryConfigs: [Region: RecoveryConfig] = [
        .unitedStates: .init(
            initialRestPeriod: 48,  // hours
            workRestriction: 7,     // days
            exerciseRestriction: 14, // days
            followupSchedule: [1, 3, 7, 14, 30, 90, 180], // days
            standardPractices: [
                .sleepElevation,
                .coldCompression,
                .medicationSchedule
            ]
        ),
        .europeanUnion: .init(
            initialRestPeriod: 72,
            workRestriction: 7,
            exerciseRestriction: 14,
            followupSchedule: [1, 3, 7, 14, 30, 90, 180],
            standardPractices: [
                .sleepElevation,
                .coldCompression,
                .medicationSchedule,
                .moistureProtection
            ]
        ),
        .southAsia: .init(
            initialRestPeriod: 72,
            workRestriction: 10,
            exerciseRestriction: 21,
            followupSchedule: [1, 3, 7, 14, 30, 90, 180],
            standardPractices: [
                .sleepElevation,
                .coldCompression,
                .medicationSchedule
            ],
            culturalPractices: [
                .ayurvedicCare(schedule: [7, 14, 30]),
                .dietaryGuidelines(restrictions: ["spicy", "tamasic"]),
                .traditionalHerbs(approved: ["aloe", "neem"]),
                .familySupport(role: .essential)
            ],
            religiousConsiderations: [
                .prayerAccommodations,
                .dietaryRestrictions,
                .fastingPeriods
            ]
        ),
        .mediterranean: .init(
            initialRestPeriod: 72,
            workRestriction: 7,
            exerciseRestriction: 14,
            followupSchedule: [1, 3, 7, 14, 30, 90, 180],
            standardPractices: [
                .sleepElevation,
                .coldCompression,
                .medicationSchedule
            ],
            culturalPractices: [
                .traditionalHerbs(approved: ["olive_oil", "chamomile"]),
                .familySupport(role: .primary),
                .dietaryGuidelines(restrictions: ["heavy_spices"])
            ],
            religiousConsiderations: [
                .prayerAccommodations,
                .fastingPeriods
            ]
        ),
        .africanDescent: .init(
            initialRestPeriod: 72,
            workRestriction: 10,
            exerciseRestriction: 21,
            followupSchedule: [1, 3, 7, 14, 30, 90, 180],
            standardPractices: [
                .sleepElevation,
                .coldCompression,
                .medicationSchedule,
                .moistureProtection
            ],
            culturalPractices: [
                .traditionalHerbs(approved: ["aloe", "shea"]),
                .hairCareRoutine(products: ["natural_oils"]),
                .communitySupport(type: .active),
                .dietaryGuidelines(restrictions: [])
            ],
            religiousConsiderations: [
                .headCovering,
                .prayerAccommodations
            ]
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func generateRecoveryPlan(
        for patient: PatientProfile,
        treatment: TreatmentPlan
    ) async throws -> RecoveryPlan {
        let region = regionManager.getCurrentRegion()
        guard let config = recoveryConfigs[region] else {
            throw RecoveryError.unsupportedRegion(region)
        }
        
        // Generate base guidelines
        var guidelines = try generateBaseGuidelines(
            config: config,
            patient: patient
        )
        
        // Add cultural practices
        if let culturalPractices = config.culturalPractices {
            guidelines.append(contentsOf: try generateCulturalGuidelines(
                practices: culturalPractices,
                patient: patient
            ))
        }
        
        // Add religious considerations
        if let religiousConsiderations = config.religiousConsiderations {
            guidelines.append(contentsOf: generateReligiousGuidelines(
                considerations: religiousConsiderations,
                patient: patient
            ))
        }
        
        // Generate timeline
        let timeline = generateRecoveryTimeline(
            config: config,
            treatment: treatment
        )
        
        // Create monitoring schedule
        let monitoring = createMonitoringSchedule(
            followups: config.followupSchedule,
            cultural: config.culturalPractices
        )
        
        let plan = RecoveryPlan(
            patientId: patient.id,
            treatmentId: treatment.id,
            guidelines: guidelines,
            timeline: timeline,
            monitoring: monitoring,
            culturalConsiderations: config.culturalPractices,
            religiousConsiderations: config.religiousConsiderations,
            createdAt: Date()
        )
        
        // Track plan generation
        trackPlanGeneration(plan, region: region)
        
        return plan
    }
    
    func validateRecoveryCompliance(
        _ compliance: RecoveryCompliance
    ) throws {
        let region = regionManager.getCurrentRegion()
        guard let config = recoveryConfigs[region] else {
            throw RecoveryError.unsupportedRegion(region)
        }
        
        // Validate standard practices
        try validateStandardPractices(
            compliance.standardPractices,
            required: config.standardPractices
        )
        
        // Validate cultural practices if applicable
        if let cultural = config.culturalPractices {
            try validateCulturalPractices(
                compliance.culturalPractices,
                required: cultural
            )
        }
        
        // Validate religious considerations if applicable
        if let religious = config.religiousConsiderations {
            try validateReligiousCompliance(
                compliance.religiousObservances,
                required: religious
            )
        }
    }
    
    func updateRecoveryPlan(
        _ plan: RecoveryPlan,
        with feedback: RecoveryFeedback
    ) async throws -> RecoveryPlan {
        var updatedPlan = plan
        
        // Analyze feedback
        let adjustments = try analyzeFeedback(feedback)
        
        // Update guidelines if needed
        if let guidelineAdjustments = adjustments.guidelineChanges {
            updatedPlan.guidelines = try adjustGuidelines(
                plan.guidelines,
                with: guidelineAdjustments
            )
        }
        
        // Update timeline if needed
        if let timelineAdjustments = adjustments.timelineChanges {
            updatedPlan.timeline = try adjustTimeline(
                plan.timeline,
                with: timelineAdjustments
            )
        }
        
        // Update monitoring if needed
        if let monitoringAdjustments = adjustments.monitoringChanges {
            updatedPlan.monitoring = try adjustMonitoring(
                plan.monitoring,
                with: monitoringAdjustments
            )
        }
        
        // Track plan update
        trackPlanUpdate(updatedPlan, feedback: feedback)
        
        return updatedPlan
    }
    
    // MARK: - Private Methods
    
    private func generateBaseGuidelines(
        config: RecoveryConfig,
        patient: PatientProfile
    ) throws -> [RecoveryGuideline] {
        var guidelines: [RecoveryGuideline] = []
        
        // Add rest period guideline
        guidelines.append(RecoveryGuideline(
            type: .rest,
            duration: config.initialRestPeriod,
            priority: .critical,
            instructions: "Complete rest for first \(config.initialRestPeriod) hours"
        ))
        
        // Add work restriction
        guidelines.append(RecoveryGuideline(
            type: .work,
            duration: config.workRestriction * 24,
            priority: .high,
            instructions: "Avoid work activities for \(config.workRestriction) days"
        ))
        
        // Add exercise restriction
        guidelines.append(RecoveryGuideline(
            type: .exercise,
            duration: config.exerciseRestriction * 24,
            priority: .high,
            instructions: "Avoid strenuous exercise for \(config.exerciseRestriction) days"
        ))
        
        // Add standard practices
        for practice in config.standardPractices {
            guidelines.append(generateStandardPracticeGuideline(practice))
        }
        
        return guidelines
    }
    
    private func generateCulturalGuidelines(
        practices: [CulturalPractice],
        patient: PatientProfile
    ) throws -> [RecoveryGuideline] {
        var guidelines: [RecoveryGuideline] = []
        
        for practice in practices {
            switch practice {
            case .ayurvedicCare(let schedule):
                guidelines.append(RecoveryGuideline(
                    type: .cultural,
                    duration: schedule.last ?? 30 * 24,
                    priority: .medium,
                    instructions: "Follow Ayurvedic care protocol",
                    schedule: schedule.map { $0 * 24 }
                ))
                
            case .traditionalHerbs(let approved):
                guidelines.append(RecoveryGuideline(
                    type: .cultural,
                    duration: 30 * 24,
                    priority: .medium,
                    instructions: "Use approved traditional herbs: \(approved.joined(separator: ", "))"
                ))
                
            case .familySupport(let role):
                guidelines.append(RecoveryGuideline(
                    type: .cultural,
                    duration: 30 * 24,
                    priority: role == .essential ? .high : .medium,
                    instructions: "Family support role: \(role)"
                ))
                
            case .dietaryGuidelines(let restrictions):
                if !restrictions.isEmpty {
                    guidelines.append(RecoveryGuideline(
                        type: .cultural,
                        duration: 30 * 24,
                        priority: .high,
                        instructions: "Avoid: \(restrictions.joined(separator: ", "))"
                    ))
                }
                
            case .hairCareRoutine(let products):
                guidelines.append(RecoveryGuideline(
                    type: .cultural,
                    duration: 90 * 24,
                    priority: .medium,
                    instructions: "Use recommended products: \(products.joined(separator: ", "))"
                ))
                
            case .communitySupport(let type):
                guidelines.append(RecoveryGuideline(
                    type: .cultural,
                    duration: 90 * 24,
                    priority: .medium,
                    instructions: "Community support type: \(type)"
                ))
            }
        }
        
        return guidelines
    }
    
    private func trackPlanGeneration(_ plan: RecoveryPlan, region: Region) {
        analytics.trackEvent(
            category: .recovery,
            action: "plan_generation",
            label: region.rawValue,
            value: 1,
            metadata: [
                "patient_id": plan.patientId.uuidString,
                "treatment_id": plan.treatmentId.uuidString,
                "guidelines_count": String(plan.guidelines.count),
                "cultural_practices": String(plan.culturalConsiderations?.count ?? 0)
            ]
        )
    }
}

// MARK: - Supporting Types

struct RecoveryConfig {
    let initialRestPeriod: Int
    let workRestriction: Int
    let exerciseRestriction: Int
    let followupSchedule: [Int]
    let standardPractices: Set<StandardPractice>
    let culturalPractices: [CulturalPractice]?
    let religiousConsiderations: Set<ReligiousConsideration>?
}

struct RecoveryPlan {
    let id: UUID = UUID()
    let patientId: UUID
    let treatmentId: UUID
    var guidelines: [RecoveryGuideline]
    let timeline: RecoveryTimeline
    var monitoring: MonitoringSchedule
    let culturalConsiderations: [CulturalPractice]?
    let religiousConsiderations: Set<ReligiousConsideration>?
    let createdAt: Date
}

struct RecoveryGuideline {
    let type: GuidelineType
    let duration: Int  // Hours
    let priority: Priority
    let instructions: String
    let schedule: [Int]?  // Hours
    
    enum GuidelineType {
        case rest
        case work
        case exercise
        case standard
        case cultural
        case religious
    }
    
    enum Priority {
        case critical
        case high
        case medium
        case optional
    }
}

enum StandardPractice {
    case sleepElevation
    case coldCompression
    case medicationSchedule
    case moistureProtection
}

enum CulturalPractice {
    case ayurvedicCare(schedule: [Int])
    case traditionalHerbs(approved: [String])
    case familySupport(role: SupportRole)
    case dietaryGuidelines(restrictions: [String])
    case hairCareRoutine(products: [String])
    case communitySupport(type: SupportType)
    
    enum SupportRole {
        case essential
        case primary
        case supportive
    }
    
    enum SupportType {
        case active
        case passive
        case periodic
    }
}

enum ReligiousConsideration {
    case prayerAccommodations
    case dietaryRestrictions
    case fastingPeriods
    case headCovering
}

struct RecoveryTimeline {
    let milestones: [RecoveryMilestone]
    let restrictions: [ActivityRestriction]
    let expectations: [ExpectedOutcome]
}

struct MonitoringSchedule {
    let checkpoints: [Checkpoint]
    let measurements: [Measurement]
    let reportingRequirements: [ReportingRequirement]
}

enum RecoveryError: LocalizedError {
    case unsupportedRegion(Region)
    case invalidGuideline(String)
    case complianceViolation(String)
    case culturalConflict(String)
    case religiousConflict(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Recovery guidelines not configured for region: \(region)"
        case .invalidGuideline(let reason):
            return "Invalid recovery guideline: \(reason)"
        case .complianceViolation(let detail):
            return "Recovery compliance violation: \(detail)"
        case .culturalConflict(let detail):
            return "Cultural practice conflict: \(detail)"
        case .religiousConflict(let detail):
            return "Religious consideration conflict: \(detail)"
        }
    }
}