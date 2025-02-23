import Foundation
import ARKit

// MARK: - Exercise Components
struct PracticalExercise {
    let id: String
    let title: String
    let description: String
    let difficulty: ExerciseDifficulty
    let success_criteria: String
    let validation: (ExercisePerformance) -> Bool
    
    enum ExerciseDifficulty {
        case beginner
        case intermediate
        case advanced
    }
}

struct ExercisePerformance {
    let accuracy: Float
    let stability: Float
    let coverage: Float
    let duration: TimeInterval
    let motionPath: [SIMD3<Float>]
    let qualityMetrics: QualityMetrics
    
    var isSuccessful: Bool {
        return accuracy >= 0.9 &&
               stability >= 0.85 &&
               coverage >= 0.95
    }
}

// MARK: - Default Exercise Sets
let defaultScanningExercises: [PracticalExercise] = [
    PracticalExercise(
        id: "scan_ex_1",
        title: "Basic Perimeter Scan",
        description: "Practice scanning the basic perimeter of the scalp",
        difficulty: .beginner,
        success_criteria: "Complete perimeter scan with 90% accuracy",
        validation: { performance in
            return validatePerimeterScan(performance)
        }
    ),
    PracticalExercise(
        id: "scan_ex_2",
        title: "Detailed Region Scanning",
        description: "Practice detailed scanning of specific regions",
        difficulty: .intermediate,
        success_criteria: "Achieve 95% detail accuracy in target regions",
        validation: { performance in
            return validateDetailedScan(performance)
        }
    ),
    PracticalExercise(
        id: "scan_ex_3",
        title: "Complex Pattern Coverage",
        description: "Practice scanning complex patterns and transitions",
        difficulty: .advanced,
        success_criteria: "Complete pattern scan with 98% coverage",
        validation: { performance in
            return validatePatternScan(performance)
        }
    )
]

// MARK: - Simulation Components
struct SimulationScenario {
    let id: String
    let title: String
    let description: String
    let difficulty: ScenarioDifficulty
    let guidePoints: [SIMD3<Float>]
    let expectedPath: [SIMD3<Float>]
    let qualityThresholds: QualityThresholds
    
    enum ScenarioDifficulty {
        case beginner
        case intermediate
        case advanced
        case expert
    }
}

struct QualityThresholds {
    let minimumAccuracy: Float
    let minimumStability: Float
    let minimumCoverage: Float
    let maximumDeviation: Float
}

let defaultScanningScenarios: [SimulationScenario] = [
    SimulationScenario(
        id: "sim_1",
        title: "Basic Coverage Pattern",
        description: "Follow the basic scanning pattern for complete coverage",
        difficulty: .beginner,
        guidePoints: generateGuidePoints(for: .basic),
        expectedPath: generateExpectedPath(for: .basic),
        qualityThresholds: QualityThresholds(
            minimumAccuracy: 0.9,
            minimumStability: 0.85,
            minimumCoverage: 0.95,
            maximumDeviation: 0.1
        )
    ),
    SimulationScenario(
        id: "sim_2",
        title: "Advanced Pattern with Transitions",
        description: "Practice smooth transitions between regions",
        difficulty: .advanced,
        guidePoints: generateGuidePoints(for: .advanced),
        expectedPath: generateExpectedPath(for: .advanced),
        qualityThresholds: QualityThresholds(
            minimumAccuracy: 0.95,
            minimumStability: 0.9,
            minimumCoverage: 0.98,
            maximumDeviation: 0.05
        )
    )
]

// MARK: - Advanced Training Scenarios
let advancedScanningScenarios: [SimulationScenario] = [
    SimulationScenario(
        id: "sim_adv_1",
        title: "Complex Pattern Recognition",
        description: "Master complex hair pattern scanning with feature preservation",
        difficulty: .expert,
        guidePoints: generateGuidePoints(for: .expert),
        expectedPath: generateExpectedPath(for: .expert),
        qualityThresholds: QualityThresholds(
            minimumAccuracy: ClinicalConstants.graftPlanningPrecision,
            minimumStability: ClinicalConstants.surfaceConsistencyThreshold,
            minimumCoverage: ClinicalConstants.densityMappingAccuracy,
            maximumDeviation: 0.02 // 2% maximum deviation as per ISHRS
        )
    ),
    SimulationScenario(
        id: "sim_adv_2",
        title: "Multi-Region Fusion",
        description: "Practice seamless fusion of multiple scalp regions",
        difficulty: .expert,
        guidePoints: generateGuidePoints(for: .expert),
        expectedPath: generateExpectedPath(for: .expert),
        qualityThresholds: QualityThresholds(
            minimumAccuracy: ClinicalConstants.featureDetectionConfidence,
            minimumStability: ClinicalConstants.surfaceConsistencyThreshold,
            minimumCoverage: ClinicalConstants.densityMappingAccuracy,
            maximumDeviation: ClinicalConstants.maxReprojectionError / 100.0
        )
    )
]

// MARK: - Guided Practice Components
struct GuidedPractice {
    let steps: [String]
    let feedback: FeedbackType
    let guidance: GuidanceSystem
    
    enum FeedbackType {
        case realtime
        case postCompletion
        case hybrid
    }
}

// MARK: - Enhanced Guidance System
class GuidanceSystem {
    let visualGuides: ARGuidanceVisuals
    let audioPrompts: AudioGuidance
    let hapticsEngine: HapticsEngine
    
    // Clinical feedback thresholds
    private let thresholds = ClinicalGuidanceThresholds(
        minFeatureDetection: ClinicalConstants.featureDetectionConfidence,
        minSurfaceConsistency: ClinicalConstants.surfaceConsistencyThreshold,
        minDensityAccuracy: ClinicalConstants.densityMappingAccuracy,
        maxReprojectionError: ClinicalConstants.maxReprojectionError
    )
    
    func provideRealtimeFeedback(for performance: ExercisePerformance) {
        // Update visual guidance
        updateVisualGuidance(performance)
        
        // Provide audio feedback
        provideAudioFeedback(performance)
        
        // Provide haptic feedback
        provideHapticFeedback(performance)
    }
    
    private func updateVisualGuidance(_ performance: ExercisePerformance) {
        // Update AR overlays based on clinical requirements
        visualGuides.updateOverlay(
            coverage: performance.coverage,
            requiredCoverage: ClinicalConstants.densityMappingAccuracy,
            qualityMetrics: performance.qualityMetrics
        )
        
        // Show feature detection confidence
        if performance.qualityMetrics.featureMatchConfidence < thresholds.minFeatureDetection {
            visualGuides.highlightLowConfidenceRegions()
        }
        
        // Display surface consistency indicators
        if performance.stability < thresholds.minSurfaceConsistency {
            visualGuides.showStabilityWarning()
        }
    }
    
    private func provideAudioFeedback(_ performance: ExercisePerformance) {
        // Provide clinical guidance based on ISHRS standards
        if performance.coverage < ClinicalConstants.densityMappingAccuracy {
            audioPrompts.playCoverageInstruction()
        }
        
        if performance.qualityMetrics.reprojectionError > thresholds.maxReprojectionError {
            audioPrompts.playMotionWarning()
        }
        
        if performance.stability < thresholds.minSurfaceConsistency {
            audioPrompts.playStabilityWarning()
        }
    }
    
    private func provideHapticFeedback(_ performance: ExercisePerformance) {
        // Provide haptic cues for quality thresholds
        if performance.coverage < ClinicalConstants.densityMappingAccuracy {
            hapticsEngine.provideCoverageHint()
        }
        
        if performance.stability < thresholds.minSurfaceConsistency {
            hapticsEngine.provideStabilityWarning()
        }
        
        // Success feedback when meeting clinical standards
        if performance.validateAgainstClinicalStandards() {
            hapticsEngine.provideSuccessFeedback()
        }
    }
}

// Supporting types for enhanced guidance
struct ClinicalGuidanceThresholds {
    let minFeatureDetection: Float
    let minSurfaceConsistency: Float
    let minDensityAccuracy: Float
    let maxReprojectionError: Float
}

extension ExercisePerformance {
    var clinicalQualityScore: Float {
        let coverageScore = coverage / ClinicalConstants.densityMappingAccuracy
        let stabilityScore = stability / ClinicalConstants.surfaceConsistencyThreshold
        let featureScore = qualityMetrics.featureMatchConfidence / ClinicalConstants.featureDetectionConfidence
        
        return (coverageScore + stabilityScore + featureScore) / 3.0
    }
    
    func generateClinicalReport() -> ClinicalTrainingReport {
        return ClinicalTrainingReport(
            accuracy: accuracy,
            coverage: coverage,
            stability: stability,
            featureDetection: qualityMetrics.featureMatchConfidence,
            reprojectionError: qualityMetrics.reprojectionError,
            passedClinicalStandards: validateAgainstClinicalStandards()
        )
    }
}

struct ClinicalTrainingReport {
    let accuracy: Float
    let coverage: Float
    let stability: Float
    let featureDetection: Float
    let reprojectionError: Float
    let passedClinicalStandards: Bool
    
    var recommendations: [String] {
        var recommendations: [String] = []
        
        if accuracy < ClinicalConstants.graftPlanningPrecision {
            recommendations.append("Improve scanning precision to meet ISHRS standards")
        }
        
        if coverage < ClinicalConstants.densityMappingAccuracy {
            recommendations.append("Ensure complete coverage as per IAAPS guidelines")
        }
        
        if stability < ClinicalConstants.surfaceConsistencyThreshold {
            recommendations.append("Maintain steady device movement for better surface consistency")
        }
        
        if featureDetection < ClinicalConstants.featureDetectionConfidence {
            recommendations.append("Improve feature detection accuracy as per latest research")
        }
        
        return recommendations
    }
}

let defaultScanningGuidedPractice = GuidedPractice(
    steps: [
        "Position device at optimal distance",
        "Start from the hairline",
        "Move in overlapping passes",
        "Maintain consistent speed",
        "Complete full coverage pattern"
    ],
    feedback: .hybrid,
    guidance: GuidanceSystem(
        visualGuides: ARGuidanceVisuals(),
        audioPrompts: AudioGuidance(),
        hapticsEngine: HapticsEngine()
    )
)

// MARK: - Assessment Components
struct AssessmentQuestion {
    let id: String
    let text: String
    let type: QuestionType
    let options: [String]?
    let correctAnswer: String
    let explanation: String
    let points: Int
    
    enum QuestionType {
        case multipleChoice
        case trueFalse
        case shortAnswer
        case practical
    }
}

struct PracticalTask {
    let id: String
    let description: String
    let successCriteria: [String]
    let evaluationMetrics: [String: Float]
    let timeLimit: TimeInterval?
    let minimumScore: Float
}

struct PassingCriteria {
    let minimumTheoryScore: Float
    let minimumPracticalScore: Float
    let requiredTasks: [String]
    let timeConstraints: TimeInterval?
}

// Default assessment content
let scanningTheoryQuestions: [AssessmentQuestion] = [
    AssessmentQuestion(
        id: "q1",
        text: "What is the optimal scanning distance for accurate results?",
        type: .multipleChoice,
        options: [
            "10-15cm",
            "20-30cm",
            "40-50cm",
            "60-70cm"
        ],
        correctAnswer: "20-30cm",
        explanation: "20-30cm provides optimal balance between detail capture and field of view",
        points: 10
    ),
    AssessmentQuestion(
        id: "q2",
        text: "Which lighting condition is most suitable for accurate scanning?",
        type: .multipleChoice,
        options: [
            "Direct sunlight",
            "Complete darkness",
            "Diffused indoor lighting",
            "Strong artificial lighting"
        ],
        correctAnswer: "Diffused indoor lighting",
        explanation: "Diffused lighting minimizes shadows and reflections while providing adequate illumination",
        points: 10
    )
]

let scanningPracticalTasks: [PracticalTask] = [
    PracticalTask(
        id: "task1",
        description: "Complete a full scalp scan meeting clinical quality requirements",
        successCriteria: [
            "Maintain optimal distance throughout scan",
            "Achieve minimum 95% coverage",
            "Keep motion stability above 0.85",
            "Complete scan within 5 minutes"
        ],
        evaluationMetrics: [
            "coverage": 0.95,
            "stability": 0.85,
            "accuracy": 0.90
        ],
        timeLimit: 300, // 5 minutes
        minimumScore: 0.9
    )
]

class ScanningPassingCriteria: PassingCriteria {
    init() {
        super.init(
            minimumTheoryScore: 0.8,
            minimumPracticalScore: 0.9,
            requiredTasks: ["task1"],
            timeConstraints: 3600 // 1 hour total
        )
    }
}

// MARK: - Enhanced Assessment Components
struct ClinicalAssessment {
    let theoreticalExam: [AssessmentQuestion]
    let practicalExam: [PracticalTask]
    let qualityMetrics: QualityAssessmentMetrics
    
    struct QualityAssessmentMetrics {
        let minimumFeatureMatchAccuracy: Float
        let minimumSurfaceConsistency: Float
        let minimumDensityAccuracy: Float
        let maximumAllowedDeviation: Float
        
        static let standard = QualityAssessmentMetrics(
            minimumFeatureMatchAccuracy: ClinicalConstants.minFeatureMatchConfidence,
            minimumSurfaceConsistency: ClinicalConstants.surfaceConsistencyThreshold,
            minimumDensityAccuracy: ClinicalConstants.densityMappingAccuracy,
            maximumAllowedDeviation: ClinicalConstants.maxReprojectionError
        )
    }
}

// Advanced practical tasks aligned with latest research
let advancedPracticalTasks: [PracticalTask] = [
    PracticalTask(
        id: "adv_task_1",
        description: "Complete high-precision multi-region scan with photogrammetry fusion",
        successCriteria: [
            "Achieve minimum feature match confidence of \(Int(ClinicalConstants.minFeatureMatchConfidence * 100))%",
            "Maintain surface consistency above \(Int(ClinicalConstants.surfaceConsistencyThreshold * 100))%",
            "Ensure density mapping accuracy of \(Int(ClinicalConstants.densityMappingAccuracy * 100))%",
            "Complete fusion with maximum reprojection error of \(ClinicalConstants.maxReprojectionError) pixels"
        ],
        evaluationMetrics: [
            "featureMatch": ClinicalConstants.minFeatureMatchConfidence,
            "surfaceConsistency": ClinicalConstants.surfaceConsistencyThreshold,
            "densityAccuracy": ClinicalConstants.densityMappingAccuracy,
            "reprojectionError": ClinicalConstants.maxReprojectionError
        ],
        timeLimit: 600, // 10 minutes
        minimumScore: ClinicalConstants.minimumFusionQuality
    )
]

// Updated validation functions with latest clinical standards
extension ExercisePerformance {
    func validateAgainstClinicalStandards() -> Bool {
        return accuracy >= ClinicalConstants.graftPlanningPrecision &&
               stability >= ClinicalConstants.surfaceConsistencyThreshold &&
               coverage >= ClinicalConstants.densityMappingAccuracy &&
               qualityMetrics.featureMatchConfidence >= ClinicalConstants.minFeatureMatchConfidence &&
               qualityMetrics.reprojectionError <= ClinicalConstants.maxReprojectionError
    }
}

// MARK: - Validation Functions
func validatePerimeterScan(_ performance: ExercisePerformance) -> Bool {
    return performance.coverage >= 0.95 &&
           performance.stability >= 0.85 &&
           performance.accuracy >= 0.9
}

func validateDetailedScan(_ performance: ExercisePerformance) -> Bool {
    return performance.coverage >= 0.98 &&
           performance.stability >= 0.9 &&
           performance.accuracy >= 0.95
}

func validatePatternScan(_ performance: ExercisePerformance) -> Bool {
    return performance.coverage >= 0.99 &&
           performance.stability >= 0.95 &&
           performance.accuracy >= 0.98
}

// MARK: - Helper Functions
func generateGuidePoints(for difficulty: SimulationScenario.ScenarioDifficulty) -> [SIMD3<Float>] {
    // Generate appropriate guide points based on difficulty
    switch difficulty {
    case .beginner:
        return generateBasicGuidePoints()
    case .intermediate:
        return generateIntermediateGuidePoints()
    case .advanced, .expert:
        return generateAdvancedGuidePoints()
    }
}

func generateExpectedPath(for difficulty: SimulationScenario.ScenarioDifficulty) -> [SIMD3<Float>] {
    // Generate expected scanning path based on difficulty
    switch difficulty {
    case .beginner:
        return generateBasicScanPath()
    case .intermediate:
        return generateIntermediateScanPath()
    case .advanced, .expert:
        return generateAdvancedScanPath()
    }
}