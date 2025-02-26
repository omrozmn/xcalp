import Foundation

class ErrorHandlingCoordinator {
    static let shared = ErrorHandlingCoordinator()
    
    private let analytics = AnalyticsService.shared
    private let localization = LocalizationManager.shared
    private let regionManager = RegionalComplianceManager.shared
    
    // Region-specific error handling strategies
    private var errorStrategies: [Region: ErrorHandlingStrategy] = [
        .unitedStates: .init(
            privacyPriority: .high,
            compliancePriority: .high,
            culturalSensitivity: .medium,
            retryPolicy: .standard
        ),
        .europeanUnion: .init(
            privacyPriority: .critical,
            compliancePriority: .high,
            culturalSensitivity: .medium,
            retryPolicy: .strict
        ),
        .southAsia: .init(
            privacyPriority: .high,
            compliancePriority: .medium,
            culturalSensitivity: .critical,
            retryPolicy: .flexible
        ),
        .mediterranean: .init(
            privacyPriority: .high,
            compliancePriority: .medium,
            culturalSensitivity: .high,
            retryPolicy: .standard
        ),
        .africanDescent: .init(
            privacyPriority: .high,
            compliancePriority: .medium,
            culturalSensitivity: .critical,
            retryPolicy: .flexible
        )
    ]
    
    private init() {}
    
    func handleError(_ error: Error) -> ErrorResolution {
        let region = regionManager.getCurrentRegion()
        let strategy = errorStrategies[region] ?? .default
        
        // Track error
        analytics.trackError(error, severity: determineSeverity(error, strategy))
        
        // Get culturally appropriate resolution
        let resolution = generateResolution(for: error, using: strategy)
        
        // Log if critical
        if resolution.severity == .critical {
            Logger.shared.critical("\(error.localizedDescription) - Resolution: \(resolution.primaryAction)")
        }
        
        return resolution
    }
    
    func handleWorkflowError(_ error: WorkflowError) -> WorkflowResolution {
        let region = regionManager.getCurrentRegion()
        let strategy = errorStrategies[region] ?? .default
        
        // Track workflow-specific error
        analytics.trackWorkflowStep(
            determineWorkflowStep(from: error),
            region: region,
            success: false
        )
        
        let resolution = generateWorkflowResolution(for: error, using: strategy)
        
        // Log if blocking
        if resolution.isBlocking {
            Logger.shared.error("Workflow blocked: \(error.localizedDescription) - Resolution: \(resolution.primaryAction)")
        }
        
        return resolution
    }
    
    private func determineSeverity(_ error: Error, _ strategy: ErrorHandlingStrategy) -> ErrorSeverity {
        switch error {
        case let workflowError as WorkflowError:
            return determineSeverity(workflowError, strategy)
        case let complianceError as ComplianceError:
            return determineSeverity(complianceError, strategy)
        case let qualityError as QualityError:
            return determineSeverity(qualityError, strategy)
        default:
            return .medium
        }
    }
    
    private func determineSeverity(_ error: WorkflowError, _ strategy: ErrorHandlingStrategy) -> ErrorSeverity {
        switch error {
        case .missingConsent, .expiredConsent:
            return strategy.privacyPriority.toSeverity()
        case .missingCulturalAssessment, .missingReligiousConsiderations:
            return strategy.culturalSensitivity.toSeverity()
        case .scanProcessingFailed, .invalidMedicalRecord:
            return .critical
        default:
            return .medium
        }
    }
    
    private func determineSeverity(_ error: ComplianceError, _ strategy: ErrorHandlingStrategy) -> ErrorSeverity {
        switch error {
        case .encryptionRequired, .authorizationRequired:
            return .critical
        case .culturalRightsRequired:
            return strategy.culturalSensitivity.toSeverity()
        default:
            return strategy.compliancePriority.toSeverity()
        }
    }
    
    private func determineSeverity(_ error: QualityError, _ strategy: ErrorHandlingStrategy) -> ErrorSeverity {
        switch error {
        case .insufficientAccuracy:
            return .high
        case .excessiveMotion:
            return strategy.retryPolicy == .strict ? .high : .medium
        default:
            return .medium
        }
    }
    
    private func generateResolution(for error: Error, using strategy: ErrorHandlingStrategy) -> ErrorResolution {
        let severity = determineSeverity(error, strategy)
        let culturalContext = localization.getCurrentSettings()
        
        return ErrorResolution(
            severity: severity,
            primaryAction: localizedPrimaryAction(for: error, context: culturalContext),
            secondaryAction: localizedSecondaryAction(for: error, context: culturalContext),
            isBlocking: severity >= .high || !isRecoverable(error),
            culturalConsiderations: culturalConsiderations(for: error, context: culturalContext)
        )
    }
    
    private func generateWorkflowResolution(for error: WorkflowError, using strategy: ErrorHandlingStrategy) -> WorkflowResolution {
        let severity = determineSeverity(error, strategy)
        let culturalContext = localization.getCurrentSettings()
        
        return WorkflowResolution(
            severity: severity,
            primaryAction: localizedPrimaryAction(for: error, context: culturalContext),
            secondaryAction: localizedSecondaryAction(for: error, context: culturalContext),
            isBlocking: severity >= .high || !error.isRecoverable,
            requiredStep: determineWorkflowStep(from: error),
            culturalConsiderations: culturalConsiderations(for: error, context: culturalContext)
        )
    }
    
    private func determineWorkflowStep(from error: WorkflowError) -> WorkflowStep {
        switch error {
        case .missingConsent, .expiredConsent:
            return .patientConsent([])
        case .missingMedicalHistory, .missingMedicalHistoryField:
            return .medicalHistory(requiredFields: [])
        case .missingPreoperativePhotos, .missingPhotoAngle:
            return .preoperativePhotos(angles: [])
        case .missingScan, .scanNotCalibrated:
            return .scan(requirements: [.calibration])
        case .missingPlanningDocs:
            return .planningDocumentation(includes: [])
        case .missingPostOpInstructions:
            return .postoperativeInstructions(format: .standard)
        case .missingCulturalAssessment:
            return .culturalAssessment(includes: [])
        }
    }
    
    private func isRecoverable(_ error: Error) -> Bool {
        switch error {
        case let workflowError as WorkflowError:
            return workflowError.isRecoverable
        case is ComplianceError:
            return true
        case is QualityError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Supporting Types

struct ErrorHandlingStrategy {
    let privacyPriority: Priority
    let compliancePriority: Priority
    let culturalSensitivity: Priority
    let retryPolicy: RetryPolicy
    
    static let `default` = ErrorHandlingStrategy(
        privacyPriority: .high,
        compliancePriority: .high,
        culturalSensitivity: .medium,
        retryPolicy: .standard
    )
    
    enum Priority {
        case low
        case medium
        case high
        case critical
        
        func toSeverity() -> ErrorSeverity {
            switch self {
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            case .critical: return .critical
            }
        }
    }
    
    enum RetryPolicy {
        case strict    // No retries
        case standard  // Limited retries
        case flexible  // More lenient retry policy
    }
}

struct ErrorResolution {
    let severity: ErrorSeverity
    let primaryAction: String
    let secondaryAction: String?
    let isBlocking: Bool
    let culturalConsiderations: [String]?
}

struct WorkflowResolution {
    let severity: ErrorSeverity
    let primaryAction: String
    let secondaryAction: String?
    let isBlocking: Bool
    let requiredStep: WorkflowStep
    let culturalConsiderations: [String]?
}

// MARK: - Private Extensions

private extension ErrorHandlingCoordinator {
    func localizedPrimaryAction(for error: Error, context: CulturalSettings) -> String {
        // Implementation would return culturally appropriate action text
        return error.localizedDescription
    }
    
    func localizedSecondaryAction(for error: Error, context: CulturalSettings) -> String? {
        // Implementation would return culturally appropriate secondary action
        return (error as? LocalizedError)?.recoverySuggestion
    }
    
    func culturalConsiderations(for error: Error, context: CulturalSettings) -> [String]? {
        // Implementation would return relevant cultural considerations
        return nil
    }
}