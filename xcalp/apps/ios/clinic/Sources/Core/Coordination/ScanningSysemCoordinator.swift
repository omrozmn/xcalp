import Foundation
import Metal
import ARKit
import CoreML
import os.log
import MetricKit

/// Central coordinator managing interactions between scanning subsystems
public final class ScanningSystemCoordinator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningSystemCoordinator")
    
    // Core processing systems
    private let meshProcessor: MeshProcessingCoordinator
    private let qualityCoordinator: ScanningQualityCoordinator
    private let performanceMonitor: PerformanceMonitor
    private let diagnosticReporter: ScanningDiagnosticReporter
    private let errorHandler: ScanningErrorHandler
    
    // Analysis systems
    private let lightingAnalyzer: LightingAnalyzer
    private let qualityAnalyzer: MeshQualityAnalyzer
    private let adaptiveQuality: AdaptiveQualityManager
    
    // Configuration
    private let config = AppConfiguration.Performance.Scanning.self
    
    // State management
    private var currentMode: ScanningMode = .lidar
    private var currentSession: UUID?
    private var isProcessingFrame = false
    private var qualityHistory: [QualityMeasurement] = []
    private var fallbackAttempts = 0
    private let maxFallbackAttempts = 3
    
    private var currentGuidanceStep: GuidanceStep?
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private var stepStartTime: Date?
    
    // Performance metrics
    private var performanceMetrics: [String: Any] = [:]
    private let metricsLogger = MXMetricManager.shared
    
    public init(device: MTLDevice) throws {
        // Initialize subsystems
        self.meshProcessor = try MeshProcessingCoordinator(device: device)
        self.qualityCoordinator = try ScanningQualityCoordinator(device: device)
        self.performanceMonitor = .shared
        self.lightingAnalyzer = try LightingAnalyzer()
        self.qualityAnalyzer = try MeshQualityAnalyzer(device: device)
        self.errorHandler = ScanningErrorHandler()
        self.adaptiveQuality = .shared
        
        // Initialize diagnostic reporter
        self.diagnosticReporter = ScanningDiagnosticReporter(
            errorHandler: errorHandler,
            performanceMonitor: performanceMonitor,
            dataStore: try ScanningDataStore.shared
        )
        
        setupPerformanceMonitoring()
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor.observe { [weak self] metrics in
            guard let self = self else { return }
            Task {
                await self.adaptiveQuality.updateQualitySettings(
                    performance: metrics,
                    environment: await self.getCurrentEnvironmentMetrics()
                )
            }
        }
    }
    
    public func startNewSession(
        mode: ScanningMode,
        configuration: ScanningConfiguration
    ) async throws {
        currentSession = UUID()
        currentMode = mode
        fallbackAttempts = 0
        
        // Create session record
        let session = try await ScanningDataStore.shared.createScanningSession(
            mode: mode,
            configuration: configuration.toDictionary(),
            timestamp: Date()
        )
        
        // Initialize subsystems
        try await initializeSubsystems(for: mode, configuration: configuration)
        
        logger.info("Started scanning session: \(session.id?.uuidString ?? "unknown")")
    }
    
    public func processFrame(_ frame: ARFrame) async throws -> FrameProcessingResult {
        guard let sessionID = currentSession else {
            throw ScanningError.invalidSession
        }
        
        // Start performance tracking
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Update guidance based on current quality
        let qualityReport = try await qualityCoordinator.processFrame(frame)
        await updateGuidance(quality: qualityReport)
        
        // Process frame with current mode settings
        let result = try await processFrameWithCurrentMode(frame, quality: qualityReport)
        
        // Update visualization
        try await updateVisualization(frame: frame, result: result)
        
        // Log performance metrics
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        performanceMetrics["frameProcessingTime"] = processingTime
        performanceMetrics["frameTimestamp"] = frame.timestamp
        logPerformanceMetrics()
        
        return result
    }
    
    private func initializeSubsystems(
        for mode: ScanningMode,
        configuration: ScanningConfiguration
    ) async throws {
        try await meshProcessor.configure(for: mode, with: configuration)
        try await qualityCoordinator.initialize(mode: mode)
        performanceMonitor.updatePhase(.scanning)
    }
    
    private func updateQualityHistory(_ quality: QualityAssessment) {
        let measurement = QualityMeasurement(
            timestamp: Date(),
            pointDensity: quality.pointDensity,
            surfaceCompleteness: quality.surfaceCompleteness,
            noiseLevel: quality.noiseLevel,
            featurePreservation: quality.featurePreservation
        )
        
        qualityHistory.append(measurement)
        
        // Keep only recent history
        qualityHistory = qualityHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -10 // Last 10 seconds
        }
    }
    
    private func handleQualityIssues(
        _ quality: QualityAssessment,
        lighting: LightingAnalysis
    ) async throws {
        // Check against thresholds
        if quality.pointDensity < config.minPointDensity ||
           quality.surfaceCompleteness < config.minSurfaceCompleteness ||
           quality.noiseLevel > config.maxNoiseLevel ||
           quality.featurePreservation < config.minFeaturePreservation {
            
            // Try fallback if available
            if fallbackAttempts < maxFallbackAttempts {
                fallbackAttempts += 1
                try await switchToFallbackMode()
            } else {
                throw ScanningError.qualityBelowThreshold
            }
        }
        
        // Check lighting conditions
        if lighting.intensity < config.minLightIntensity {
            throw ScanningError.insufficientLighting
        }
    }
    
    private func switchToFallbackMode() async throws {
        switch currentMode {
        case .lidar:
            currentMode = .photogrammetry
        case .photogrammetry:
            currentMode = .hybrid
        case .hybrid:
            throw ScanningError.noFallbackAvailable
        }
        
        try await initializeSubsystems(
            for: currentMode,
            configuration: ScanningConfiguration()
        )
    }
    
    private func processMeshIfQualityAcceptable(
        frame: ARFrame,
        quality: QualityAssessment
    ) async throws -> ProcessedMesh {
        guard quality.isAcceptable else {
            throw ScanningError.qualityBelowThreshold
        }
        
        return try await meshProcessor.processMesh(
            frame: frame,
            quality: quality
        )
    }
    
    private func getCurrentEnvironmentMetrics() async -> EnvironmentMetrics {
        // Get current environment conditions for adaptive quality
        return EnvironmentMetrics(
            lightingLevel: qualityHistory.last?.lightingScore ?? 1.0,
            motionStability: qualityHistory.last?.motionScore ?? 1.0,
            surfaceComplexity: qualityHistory.last?.complexityScore ?? 0.5
        )
    }
    
    private func handleProcessingError(_ error: Error) async {
        logger.error("Processing error: \(error.localizedDescription)")
        
        // Structured error recovery
        let recoveryResult = await attemptErrorRecovery(for: error)
        
        if recoveryResult.success {
            logger.info("Error recovery successful")
            return
        }
        
        // If recovery failed, handle the error
        errorHandler.handle(error, severity: .high)
        
        if let scanningError = error as? ScanningError {
            switch scanningError {
            case .qualityBelowThreshold:
                await diagnosticReporter.reportQualityIssue(qualityHistory.last)
            case .insufficientLighting:
                await diagnosticReporter.reportLightingIssue()
            default:
                break
            }
        }
        
        // Provide user feedback about the error
        await provideErrorFeedback(error: error, recoveryAttempted: recoveryResult.attempted)
    }
    
    private func attemptErrorRecovery(for error: Error) async -> (attempted: Bool, success: Bool) {
        guard let scanningError = error as? ScanningError else {
            return (false, false)
        }
        
        switch scanningError {
        case .qualityBelowThreshold:
            do {
                try await switchToFallbackMode()
                return (true, true)
            } catch {
                return (true, false)
            }
            
        case .insufficientLighting:
            // Attempt to adjust lighting settings
            return (true, await adjustLightingSettings())
            
        default:
            return (false, false)
        }
    }
    
    private func provideErrorFeedback(error: Error, recoveryAttempted: Bool) async {
        let feedbackMessage: String
        let hapticPattern: HapticPattern
        
        if recoveryAttempted {
            feedbackMessage = "We couldn't automatically fix the issue. Please check the following:"
            hapticPattern = .error
        } else {
            feedbackMessage = "An error occurred during scanning:"
            hapticPattern = .warning
        }
        
        // Provide voice feedback
        SpeechSynthesizer.shared.speak(feedbackMessage)
        
        // Provide haptic feedback
        feedbackGenerator.notificationOccurred(hapticPattern == .error ? .error : .warning)
        
        // Show visual error details
        NotificationCenter.default.post(
            name: .scanningErrorOccurred,
            object: nil,
            userInfo: [
                "error": error.localizedDescription,
                "recoveryAttempted": recoveryAttempted
            ]
        )
    }
    
    private func updateGuidance(quality: QualityAssessment) async {
        guard let currentStep = currentGuidanceStep else {
            // Initialize first step
            currentGuidanceStep = enhancedGuidanceSteps.first
            stepStartTime = Date()
            provideFeedback(for: enhancedGuidanceSteps.first!)
            return
        }
        
        // Check if current step requirements are met
        if meetsQualityThresholds(quality: quality, thresholds: currentStep.qualityThresholds) {
            let stepDuration = Date().timeIntervalSince(stepStartTime ?? Date())
            
            // Only advance if minimum duration is met
            if stepDuration >= currentStep.minDuration {
                advanceToNextStep()
            }
        } else {
            // Provide recovery guidance
            provideRecoveryFeedback(for: currentStep)
        }
    }
    
    private func advanceToNextStep() {
        guard let currentIndex = enhancedGuidanceSteps.firstIndex(where: { $0.phase == currentGuidanceStep?.phase }) else {
            return
        }
        
        let nextIndex = enhancedGuidanceSteps.index(after: currentIndex)
        guard nextIndex < enhancedGuidanceSteps.endIndex else {
            // Scanning complete
            completeScan()
            return
        }
        
        currentGuidanceStep = enhancedGuidanceSteps[nextIndex]
        stepStartTime = Date()
        provideFeedback(for: enhancedGuidanceSteps[nextIndex])
    }
    
    private func provideFeedback(for step: GuidanceStep) {
        // Voice guidance
        SpeechSynthesizer.shared.speak(step.voicePrompt)
        
        // Haptic feedback
        switch step.hapticPattern {
        case .singleTap:
            feedbackGenerator.notificationOccurred(.success)
        case .continuousFeedback:
            feedbackGenerator.notificationOccurred(.warning)
        case .dynamicFeedback:
            feedbackGenerator.notificationOccurred(.error)
        case .preciseFeedback:
            // Custom haptic pattern for precise feedback
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
        case .success:
            feedbackGenerator.notificationOccurred(.success)
        }
        
        // Visual guide update through notification
        NotificationCenter.default.post(
            name: .guidanceStepChanged,
            object: nil,
            userInfo: ["step": step]
        )
    }
    
    private func provideRecoveryFeedback(for step: GuidanceStep) {
        guard let recoveryPrompt = step.recoveryPrompt else { return }
        
        // Voice recovery guidance
        SpeechSynthesizer.shared.speak(recoveryPrompt)
        
        // Haptic warning
        feedbackGenerator.notificationOccurred(.warning)
        
        // Visual recovery guide
        NotificationCenter.default.post(
            name: .guidanceRecoveryNeeded,
            object: nil,
            userInfo: [
                "step": step,
                "recoveryPrompt": recoveryPrompt
            ]
        )
    }
    
    private func completeScan() {
        // Log final metrics
        logPerformanceMetrics()
        NotificationCenter.default.post(name: .scanningComplete, object: nil)
    }
    
    private func logPerformanceMetrics() {
        let payload = MXMetricPayload(
            latestApplicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            metrics: performanceMetrics
        )
        metricsLogger.submit(payload)
    }
}

// MARK: - Supporting Types

struct ScanningConfiguration {
    let qualityPreset: MeshQualityConfig.QualityPreset
    let optimizationParameters: MeshOptimizer.OptimizationParameters
    let validationStages: Set<MeshValidationSystem.ValidationStage>
    let reconstructionOptions: MeshReconstructor.ReconstructionOptions
    let qualityThresholds: MeshQualityConfig.QualityThresholds
    
    func toDictionary() -> [String: Any] {
        // Convert configuration to dictionary for storage
        return [:]  // Implementation needed
    }
}

struct FrameProcessingResult {
    let mesh: ProcessedMesh
    let quality: QualityAssessment
    let lighting: LightingAnalysis
    let diagnostics: DiagnosticSummary
}

enum ScanningError: Error {
    case invalidSession
    case processingInProgress
    case deviceNotSupported
    case invalidFrameData
    case qualityBelowThreshold
    case unrecoverableError
    case insufficientLighting
    case noFallbackAvailable
}
