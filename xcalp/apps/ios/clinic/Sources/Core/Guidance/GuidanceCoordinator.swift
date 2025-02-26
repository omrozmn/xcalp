import Foundation
import ARKit
import CoreHaptics
import Combine

public final class GuidanceCoordinator {
    // Components
    private let voiceGuidance: VoiceGuidanceManager
    private let hapticEngine: HapticEngine
    private let visualGuidance: VisualGuidanceController
    
    // State management
    private var currentPhase: GuidanceProtocol.ScanningPhase = .preparation
    private var currentStepIndex = 0
    private var cancellables = Set<AnyCancellable>()
    
    // Quality monitoring
    private let qualityMonitor: ScanQualityMonitor
    private var lastQualityUpdate = Date()
    private let qualityUpdateInterval: TimeInterval = 0.5
    
    // Performance metrics
    private let performanceMonitor = PerformanceMonitor.shared
    private var metrics = PerformanceMetrics()
    
    public init() throws {
        self.voiceGuidance = VoiceGuidanceManager.shared
        self.hapticEngine = try HapticEngine()
        self.visualGuidance = VisualGuidanceController()
        self.qualityMonitor = ScanQualityMonitor()
        
        setupQualityMonitoring()
        setupPerformanceTracking()
    }
    
    // MARK: - Public Interface
    
    public func startGuidance() {
        currentPhase = .preparation
        currentStepIndex = 0
        
        // Start monitoring systems
        qualityMonitor.startMonitoring()
        performanceMonitor.startSession()
        
        // Begin first step
        executeCurrentStep()
    }
    
    public func processFrame(_ frame: ARFrame) {
        let perfID = performanceMonitor.startMeasuring("frameProcessing")
        defer { performanceMonitor.endMeasuring("frameProcessing", signpostID: perfID) }
        
        // Update quality metrics
        updateQualityMetrics(frame)
        
        // Check if we should advance to next step
        checkStepProgression()
        
        // Update visual guidance
        updateVisualGuidance(frame)
    }
    
    public func pauseGuidance() {
        voiceGuidance.stop()
        hapticEngine.stop()
        visualGuidance.pause()
        qualityMonitor.pauseMonitoring()
    }
    
    public func resumeGuidance() {
        qualityMonitor.resumeMonitoring()
        visualGuidance.resume()
        executeCurrentStep()
    }
    
    // MARK: - Private Methods
    
    private func setupQualityMonitoring() {
        qualityMonitor.$qualityMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.handleQualityUpdate(metrics)
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceTracking() {
        performanceMonitor.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.metrics = metrics
                self?.checkPerformanceThresholds()
            }
            .store(in: &cancellables)
    }
    
    private func executeCurrentStep() {
        guard currentStepIndex < GuidanceProtocol.clinicalWorkflow.count else {
            handleScanCompletion()
            return
        }
        
        let step = GuidanceProtocol.clinicalWorkflow[currentStepIndex]
        
        // Update phase if needed
        if currentPhase != step.phase {
            currentPhase = step.phase
            NotificationCenter.default.post(
                name: Notification.Name("ScanningPhaseChanged"),
                object: nil,
                userInfo: ["phase": currentPhase]
            )
        }
        
        // Provide guidance
        voiceGuidance.provideGuidance(step.voicePrompt)
        hapticEngine.playPattern(step.hapticPattern)
        visualGuidance.showGuide(step.visualGuide)
        
        // Log step execution
        performanceMonitor.logEvent(
            "guidance_step_started",
            metadata: [
                "phase": currentPhase,
                "step": currentStepIndex,
                "timestamp": Date()
            ]
        )
    }
    
    private func handleQualityUpdate(_ metrics: ScanQualityMetrics) {
        guard Date().timeIntervalSince(lastQualityUpdate) >= qualityUpdateInterval else { return }
        lastQualityUpdate = Date()
        
        let currentStep = GuidanceProtocol.clinicalWorkflow[currentStepIndex]
        
        // Validate quality against thresholds
        if !GuidanceProtocol.validateQuality(metrics: metrics, phase: currentPhase) {
            handleQualityIssue(metrics, currentStep)
        } else if currentStep.autoAdvance {
            advanceToNextStep()
        }
    }
    
    private func handleQualityIssue(_ metrics: ScanQualityMetrics, _ step: GuidanceProtocol.GuidanceStep) {
        // Determine specific quality issues
        if metrics.pointDensity < step.qualityThresholds.pointDensity {
            voiceGuidance.provideGuidance("Move closer to capture more detail")
            hapticEngine.playPattern(.warning)
        }
        
        if metrics.motionStability < step.qualityThresholds.motionStability {
            voiceGuidance.provideGuidance("Please hold the device more steady")
            hapticEngine.playPattern(.warning)
        }
        
        if metrics.lightingQuality < step.qualityThresholds.lightingQuality {
            voiceGuidance.provideGuidance("Improve lighting for better quality")
            hapticEngine.playPattern(.warning)
        }
        
        // Update visual feedback
        visualGuidance.showQualityFeedback(metrics)
    }
    
    private func checkStepProgression() {
        let currentStep = GuidanceProtocol.clinicalWorkflow[currentStepIndex]
        
        if currentStep.autoAdvance {
            // Check if quality thresholds are met
            if let metrics = qualityMonitor.currentMetrics,
               GuidanceProtocol.validateQuality(metrics: metrics, phase: currentPhase) {
                advanceToNextStep()
            }
        }
    }
    
    private func advanceToNextStep() {
        currentStepIndex += 1
        
        if currentStepIndex < GuidanceProtocol.clinicalWorkflow.count {
            executeCurrentStep()
        } else {
            handleScanCompletion()
        }
    }
    
    private func updateVisualGuidance(_ frame: ARFrame) {
        let step = GuidanceProtocol.clinicalWorkflow[currentStepIndex]
        
        switch step.phase {
        case .preparation:
            visualGuidance.updateEnvironmentCheck(frame)
        case .positioning:
            visualGuidance.updatePositioningGuide(frame)
        case .scanning:
            visualGuidance.updateScanningGuide(frame)
        case .verification:
            visualGuidance.updateQualityCheck(frame)
        case .completion:
            visualGuidance.showCompletionStatus()
        }
    }
    
    private func checkPerformanceThresholds() {
        if metrics.frameRate < 30 {
            performanceMonitor.logWarning("Frame rate dropped below 30fps")
        }
        
        if metrics.memoryUsage > 200 * 1024 * 1024 { // 200MB
            performanceMonitor.logWarning("Memory usage exceeded 200MB")
        }
        
        if metrics.processingTime > 5.0 {
            performanceMonitor.logWarning("Processing time exceeded 5 seconds")
        }
    }
    
    private func handleScanCompletion() {
        voiceGuidance.provideGuidance("Scan complete")
        hapticEngine.playPattern(.success)
        visualGuidance.showCompletionStatus()
        
        // Log final metrics
        performanceMonitor.logEvent(
            "scan_completed",
            metadata: [
                "duration": performanceMonitor.sessionDuration,
                "quality_score": qualityMonitor.currentMetrics?.overallQuality ?? 0,
                "final_phase": currentPhase
            ]
        )
        
        NotificationCenter.default.post(name: Notification.Name("ScanningComplete"), object: nil)
    }
}