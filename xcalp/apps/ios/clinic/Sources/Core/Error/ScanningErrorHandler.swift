import Foundation
import ARKit
import Metal
import os.log

final class ScanningErrorHandler {
    static let shared = ScanningErrorHandler()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningErrors")
    private let recoveryManager = ErrorRecoveryManager()
    private let performanceMonitor = PerformanceMonitor.shared
    
    private var errorHistory: RingBuffer<ErrorEvent>
    private var recoveryAttempts: [UUID: Int] = [:]
    private let maxRecoveryAttempts = 3
    private let errorThrottleInterval: TimeInterval = 1.0
    
    private init() {
        self.errorHistory = RingBuffer(capacity: 100)
        setupNotificationObservers()
    }
    
    // MARK: - Error Handling
    
    func handle(_ error: Error, context: ScanningContext) async throws {
        let errorID = UUID()
        let event = ErrorEvent(id: errorID, error: error, context: context, timestamp: Date())
        errorHistory.append(event)
        
        // Log error with context
        logError(event)
        
        // Check if we should attempt recovery
        if shouldAttemptRecovery(for: error, withID: errorID) {
            try await performRecovery(from: error, context: context, errorID: errorID)
        } else {
            // Propagate error if recovery not possible or exceeded attempts
            throw error
        }
    }
    
    func registerCustomRecoveryStrategy(
        for errorType: Error.Type,
        strategy: @escaping (Error, ScanningContext) async throws -> Void
    ) {
        recoveryManager.registerStrategy(for: errorType, strategy: strategy)
    }
    
    // MARK: - Private Methods
    
    private func shouldAttemptRecovery(for error: Error, withID errorID: UUID) -> Bool {
        let attempts = recoveryAttempts[errorID] ?? 0
        guard attempts < maxRecoveryAttempts else {
            logger.error("Max recovery attempts exceeded for error: \(errorID)")
            return false
        }
        
        // Check if similar errors occurred recently
        let recentErrors = errorHistory.elements.filter {
            $0.timestamp > Date().addingTimeInterval(-errorThrottleInterval) &&
            type(of: $0.error) == type(of: error)
        }
        
        guard recentErrors.count < 3 else {
            logger.error("Too many similar errors in short time period")
            return false
        }
        
        return true
    }
    
    private func performRecovery(
        from error: Error,
        context: ScanningContext,
        errorID: UUID
    ) async throws {
        let attempts = recoveryAttempts[errorID] ?? 0
        recoveryAttempts[errorID] = attempts + 1
        
        // Record metrics before recovery attempt
        let preRecoveryMetrics = performanceMonitor.getCurrentMetrics()
        
        do {
            let strategy = try determineRecoveryStrategy(for: error, context: context)
            try await executeRecoveryStrategy(strategy, error: error, context: context)
            
            // Validate recovery success
            try await validateRecoveryResult(context: context)
            
            // Record successful recovery
            recordSuccessfulRecovery(errorID: errorID, error: error)
            
        } catch {
            logger.error("Recovery failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func determineRecoveryStrategy(
        for error: Error,
        context: ScanningContext
    ) throws -> RecoveryStrategy {
        // Log error for analysis
        logger.error("Determining recovery strategy for error: \(error.localizedDescription)")
        
        switch error {
        case let trackingError as ARError where trackingError.code == .worldTrackingFailed:
            notifyUser(guidance: "Hold the device steady and ensure good lighting")
            return .resetTracking
            
        case let qualityError as ScanQualityError:
            let strategy = determineQualityRecoveryStrategy(qualityError, context: context)
            logRecoveryAttempt(error: qualityError, strategy: strategy)
            return strategy
            
        case let processingError as ProcessingError:
            let strategy = determineProcessingRecoveryStrategy(processingError, context: context)
            logRecoveryAttempt(error: processingError, strategy: strategy)
            return strategy
            
        case let performanceError as PerformanceError:
            let strategy = determinePerformanceRecoveryStrategy(performanceError, context: context)
            logRecoveryAttempt(error: performanceError, strategy: strategy)
            return strategy
            
        default:
            // Implement progressive recovery for unknown errors
            return determineProgressiveRecovery(context: context)
        }
    }
    
    private func determineQualityRecoveryStrategy(
        _ error: ScanQualityError,
        context: ScanningContext
    ) -> RecoveryStrategy {
        switch error {
        case .insufficientLighting(let current, let required):
            return .adjustQualityThresholds(
                settings: QualitySettings(
                    lightingThreshold: max(current * 0.8, required * 0.9),
                    processingQuality: .medium
                )
            )
            
        case .insufficientFeatures(let count, _):
            return .adjustScanningDistance(
                current: context.scanningDistance,
                target: count < 100 ? 0.3 : 0.5
            )
            
        case .excessiveMotion:
            return .pauseAndStabilize(duration: 2.0)
            
        default:
            return .resetAndRetry
        }
    }
    
    private func determineProcessingRecoveryStrategy(
        _ error: ProcessingError,
        context: ScanningContext
    ) -> RecoveryStrategy {
        switch error {
        case .resourceExhaustion:
            return .optimizeResources(
                target: .memory,
                settings: QualitySettings(
                    processingQuality: .medium,
                    batchSize: 500
                )
            )
            
        case .processingTimeout:
            return .optimizeResources(
                target: .speed,
                settings: QualitySettings(
                    processingQuality: .low,
                    batchSize: 200
                )
            )
            
        default:
            return .resetAndRetry
        }
    }
    
    private func determinePerformanceRecoveryStrategy(
        _ error: PerformanceError,
        context: ScanningContext
    ) -> RecoveryStrategy {
        switch error {
        case .highMemoryUsage:
            return .optimizeResources(
                target: .memory,
                settings: QualitySettings(
                    processingQuality: .low,
                    batchSize: 100
                )
            )
            
        case .lowFrameRate:
            return .optimizeResources(
                target: .speed,
                settings: QualitySettings(
                    processingQuality: .medium,
                    featureQualityThreshold: 0.7
                )
            )
            
        default:
            return .resetAndRetry
        }
    }
    
    private func determineProgressiveRecovery(context: ScanningContext) -> RecoveryStrategy {
        let previousAttempts = recoveryHistory.filter { $0.timestamp > Date().addingTimeInterval(-300) }
        
        switch previousAttempts.count {
        case 0:
            return .pauseAndStabilize(duration: 2.0)
        case 1:
            return .adjustQualityThresholds(settings: QualitySettings(processingQuality: .medium))
        case 2:
            return .optimizeResources(target: .memory, settings: QualitySettings(processingQuality: .low))
        default:
            return .resetAndRetry
        }
    }
    
    private func executeRecoveryStrategy(
        _ strategy: RecoveryStrategy,
        error: Error,
        context: ScanningContext
    ) async throws {
        logger.info("Executing recovery strategy: \(String(describing: strategy))")
        
        switch strategy {
        case .resetTracking:
            NotificationCenter.default.post(name: .resetTrackingRequired, object: nil)
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
        case .adjustQualityThresholds(let settings):
            AdaptiveQualityManager.shared.forceQualityUpdate(
                to: settings,
                reason: .errorRecovery
            )
            
        case .optimizeResources(let target, let settings):
            performanceMonitor.applyOptimizationStrategy(target, with: settings)
            
        case .pauseAndStabilize(let duration):
            NotificationCenter.default.post(
                name: .scanningPaused,
                object: nil,
                userInfo: ["duration": duration]
            )
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
        case .adjustScanningDistance(_, let target):
            NotificationCenter.default.post(
                name: .adjustScanningDistance,
                object: nil,
                userInfo: ["targetDistance": target]
            )
            
        case .resetAndRetry:
            try await executeResetAndRetry(context: context)
        }
    }
    
    private func validateRecoveryResult(context: ScanningContext) async throws {
        // Check if error conditions have been resolved
        let currentMetrics = performanceMonitor.getCurrentMetrics()
        
        guard currentMetrics.memoryUsage < 150_000_000 else {
            throw RecoveryError.resourceConstraintsNotMet
        }
        
        guard currentMetrics.frameRate >= 25 else {
            throw RecoveryError.performanceTargetNotMet
        }
        
        // Validate scanning conditions
        try await validateScanningConditions(context)
    }
    
    private func validateScanningConditions(_ context: ScanningContext) async throws {
        guard let frame = context.currentFrame else {
            throw RecoveryError.invalidContext
        }
        
        // Check tracking state
        if case .limited(let reason) = frame.camera.trackingState {
            throw RecoveryError.trackingNotRestored(reason)
        }
        
        // Check lighting
        let lighting = frame.lightEstimate?.ambientIntensity ?? 0
        guard lighting >= ClinicalConstants.minimumScanLightingLux else {
            throw RecoveryError.insufficientLighting
        }
        
        // Check motion stability
        let motion = calculateMotionStability(frame.camera)
        guard motion >= ClinicalConstants.minimumMotionStability else {
            throw RecoveryError.excessiveMotion
        }
    }
    
    private func recordSuccessfulRecovery(errorID: UUID, error: Error) {
        logger.info("Successfully recovered from error: \(errorID)")
        recoveryAttempts.removeValue(forKey: errorID)
        
        NotificationCenter.default.post(
            name: .errorRecoverySucceeded,
            object: nil,
            userInfo: [
                "errorID": errorID,
                "errorType": String(describing: type(of: error))
            ]
        )
    }
    
    private func logError(_ event: ErrorEvent) {
        logger.error("""
            Scanning error occurred:
            ID: \(event.id)
            Type: \(String(describing: type(of: event.error)))
            Description: \(event.error.localizedDescription)
            Context: \(String(describing: event.context))
            """)
    }
    
    private func logRecoveryAttempt(error: Error, strategy: RecoveryStrategy) {
        recoveryHistory.append(RecoveryAttempt(
            timestamp: Date(),
            errorType: String(describing: type(of: error)),
            strategy: strategy,
            context: [
                "error_description": error.localizedDescription,
                "strategy_type": String(describing: strategy)
            ]
        ))
        
        // Trim history to last 24 hours
        recoveryHistory = recoveryHistory.filter { 
            $0.timestamp > Date().addingTimeInterval(-86400)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleThermalStateChange(_ notification: Notification) {
        guard let processInfo = notification.object as? ProcessInfo else { return }
        
        switch processInfo.thermalState {
        case .serious, .critical:
            AdaptiveQualityManager.shared.forceQualityUpdate(
                to: QualitySettings(
                    processingQuality: .low,
                    batchSize: 100
                ),
                reason: .thermalMitigation
            )
        default:
            break
        }
    }
}

// MARK: - Supporting Types

struct ErrorEvent {
    let id: UUID
    let error: Error
    let context: ScanningContext
    let timestamp: Date
}

struct ScanningContext {
    let currentFrame: ARFrame?
    let scanningDistance: Float
    let qualitySettings: QualitySettings
    let performanceMetrics: ResourceMetrics
}

enum RecoveryStrategy {
    case resetTracking
    case adjustQualityThresholds(settings: QualitySettings)
    case optimizeResources(target: ResourceTarget, settings: QualitySettings)
    case pauseAndStabilize(duration: TimeInterval)
    case adjustScanningDistance(current: Float, target: Float)
    case resetAndRetry
}

enum RecoveryError: Error {
    case resourceConstraintsNotMet
    case performanceTargetNotMet
    case invalidContext
    case trackingNotRestored(ARCamera.TrackingState.Reason)
    case insufficientLighting
    case excessiveMotion
}

extension Notification.Name {
    static let resetTrackingRequired = Notification.Name("resetTrackingRequired")
    static let scanningPaused = Notification.Name("scanningPaused")
    static let adjustScanningDistance = Notification.Name("adjustScanningDistance")
    static let errorRecoverySucceeded = Notification.Name("errorRecoverySucceeded")
}