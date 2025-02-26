import Combine
import ComposableArchitecture
import CoreHaptics
import Foundation
import RealityKit
import SwiftUI

public final class ScanningFeature: ObservableObject {
    private let capabilityChecker = DeviceCapabilityChecker.shared
    private var arSession: ARSession?
    private var sessionDelegate: ScanningSessionDelegate?
    private var meshProcessor: MeshProcessor?
    private var capturedPoints: [Point3D] = []
    private let captureProgressManager = CaptureProgressManager()
    private let hapticManager = HapticFeedbackManager()
    private let voiceFeedback = VoiceFeedbackManager()
    private let recoveryManager = ScanningRecoveryManager()
    private let cacheManager = ScanningCacheManager()
    private var systemMonitor: ScanningSystemMonitor?
    private let sessionStorage = ScanningSessionStorage()
    private var currentSessionId: UUID?
    private var visualizationController: PointCloudVisualizationController?
    @Published var visualizationMode: VisualizationMode = .points
    @Published private(set) var currentVisualization: ModelEntity?
    
    @Published private(set) var scanningCapabilities: ScanningCapabilities
    @Published private(set) var selectedCamera: ScanningCamera?
    @Published private(set) var scanningState: ScanningState = .idle
    @Published private(set) var scanningQuality: Float = 0.0
    @Published private(set) var guidanceMessage: String = ""
    @Published private(set) var captureProgress: Float = 0.0
    @Published private(set) var captureStage: CaptureProgressManager.CaptureStage?
    @Published var isVoiceFeedbackEnabled: Bool = true {
        didSet {
            voiceFeedback.isEnabled = isVoiceFeedbackEnabled
        }
    }
    @Published private(set) var isRecovering = false
    @Published private(set) var recoveryProgress: Float = 0.0
    @Published private(set) var systemStatus: SystemStatus = .optimal
    @Published var availableSessions: [ScanSession] = []
    @Published private(set) var isResumingSession = false
    private let pointCloudOptimizer = PointCloudOptimizer()
    private let optimizationQueue = DispatchQueue(label: "com.xcalp.pointCloudOptimization")
    @Published private(set) var isOptimizing = false
    private var environmentValidator: EnvironmentValidator?
    @Published private(set) var environmentConditions: [EnvironmentStatus] = []
    @Published private(set) var isEnvironmentValid = false
    private var motionBlurCompensator: MotionBlurCompensator?
    @Published private(set) var currentBlurAmount: Float = 0
    @Published private(set) var isCompensatingBlur = false
    private let coverageTracker = ScanCoverageTracker()
    @Published private(set) var scanCoverage: Float = 0
    @Published private(set) var coverageHeatmap: [(position: SIMD3<Float>, density: Float)] = []
    private let errorHandler = ScanningErrorHandler()
    @Published private(set) var currentError: ScanningError?
    @Published private(set) var isRetrying = false
    private var performanceMonitor: ScanningPerformanceMonitor?
    @Published private(set) var currentMetrics: ScanningMetrics?
    @Published private(set) var isPerformanceOptimal = true
    private var optimizationGuide: ScanningOptimizationGuide?
    private var speedController: AdaptiveScanningSpeedController?
    @Published private(set) var currentHints: [OptimizationHint] = []
    @Published private(set) var currentSpeed: Float = 0
    @Published private(set) var optimizedSpeed: Float = 0.5
    @Published private(set) var speedGuidance: String = ""
    @Published private(set) var showingScanningGuide = true
    @Published private(set) var guideMessage = ""
    private var lastGuidanceTime: TimeInterval = 0
    private let guidanceInterval: TimeInterval = 2.0
    private var preferences = ScanningPreferences()
    private var previewViewModel: ScanningPreviewViewModel?
    private var lastPosition: SIMD3<Float>?
    private var lastAudioUpdate: TimeInterval = 0
    private let audioUpdateInterval: TimeInterval = 0.1
    @Published private(set) var showingMetrics: Bool
    @Published private(set) var showingSpeedGauge: Bool
    @Published private(set) var showingCoverageMap: Bool
    
    public init() {
        self.scanningCapabilities = capabilityChecker.validateScanningCapabilities()
        self.arSession = ARSession()
        
        // Initialize UI state from preferences
        self.showingMetrics = preferences.showQualityMetrics
        self.showingSpeedGauge = preferences.showSpeedGauge
        self.showingCoverageMap = preferences.showCoverageMap
        
        do {
            self.meshProcessor = try MeshProcessor()
            if let device = MTLCreateSystemDefaultDevice() {
                self.visualizationController = PointCloudVisualizationController(device: device)
            }
            self.availableSessions = try sessionStorage.listSessions()
            setupMotionBlurCompensation()
            setupErrorHandling()
            setupPerformanceMonitoring()
            setupOptimizationGuide()
            setupSpeedController()
            setupPreviewViewModel()
        } catch {
            print("Failed to initialize: \(error)")
        }
        
        setupSessionDelegate()
        setupCaptureProgress()
        setupRecoveryCallbacks()
        setupSystemMonitoring()
        setupAutosave()
        setupEnvironmentValidation()
        
        // Observe visualization mode changes
        $visualizationMode
            .sink { [weak self] mode in
                self?.updateVisualization(mode: mode)
            }
            .store(in: &cancellables)
        
        // Configure feedback systems based on preferences
        configureFeedbackSystems()
    }
    
    private func updateVisualization(mode: VisualizationMode) {
        guard let points = capturedPoints,
              let controller = visualizationController,
              !isOptimizing else {
            return
        }
        
        currentVisualization = controller.updateVisualization(
            points: points,
            quality: scanningQuality,
            mode: mode
        )
    }
    
    private func setupSessionDelegate() {
        sessionDelegate = ScanningSessionDelegate(
            onQualityUpdate: { [weak self] quality in
                DispatchQueue.main.async {
                    self?.scanningQuality = quality
                    self?.hapticManager.playQualityFeedback(quality)
                    self?.voiceFeedback.speakQualityFeedback(quality)
                    
                    // Process and cache points
                    if let points = self?.capturedPoints {
                        self?.processNewPoints(points)
                        self?.cacheManager.cachePoints(points, quality: quality)
                        self?.recoveryManager.saveState(points, quality: quality)
                        
                        // Update performance metrics
                        self?.performanceMonitor?.recordPointCount(points.count)
                    }
                }
            },
            onFrame: { [weak self] frame in
                guard let self = self else { return }
                
                // Record frame for performance monitoring
                self.performanceMonitor?.recordFrame()
                
                // Update scanning feedback
                self.updateScanningFeedback(frame)
                
                // Update scanning speed
                self.speedController?.updateSpeed(
                    frame: frame,
                    quality: self.scanningQuality,
                    coverage: self.scanCoverage
                )
                
                // Validate environment conditions
                self.environmentValidator?.validateEnvironment(frame: frame)
                
                // Process frame for motion blur
                if let pixelBuffer = frame.capturedImage {
                    _ = self.motionBlurCompensator?.processFrame(pixelBuffer)
                }
                
                // Analyze scanning technique
                if let points = self.capturedPoints {
                    self.optimizationGuide?.analyzeScanningSession(
                        frame: frame,
                        quality: self.scanningQuality,
                        coverage: self.scanCoverage,
                        points: points
                    )
                }
                
                self.provideFeedback(frame: frame)
            },
            onGuidanceUpdate: { [weak self] guidance in
                DispatchQueue.main.async {
                    self?.guidanceMessage = guidance
                    self?.voiceFeedback.speakGuidance(guidance)
                }
            },
            onFailure: { [weak self] error in
                DispatchQueue.main.async {
                    self?.handleScanningFailure(error: error)
                }
            },
            onProcessingComplete: { [weak self] duration in
                // Record processing time for performance monitoring
                self?.performanceMonitor?.recordProcessingTime(duration)
            }
        )
        
        arSession?.delegate = sessionDelegate
    }
    
    private func setupCaptureProgress() {
        captureProgressManager.setProgressHandler { [weak self] stage in
            DispatchQueue.main.async {
                self?.captureStage = stage
                self?.captureProgress = stage.progress
                self?.hapticManager.playProgressFeedback(stage.progress)
                self?.voiceFeedback.speakCaptureProgress(stage)
            }
        }
    }
    
    private func setupRecoveryCallbacks() {
        recoveryManager.setRecoveryCallbacks(
            onStarted: { [weak self] in
                DispatchQueue.main.async {
                    self?.isRecovering = true
                    self?.guidanceMessage = "Attempting to recover scan..."
                }
            },
            onProgress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.recoveryProgress = progress
                }
            },
            onCompleted: { [weak self] success in
                DispatchQueue.main.async {
                    self?.isRecovering = false
                    self?.guidanceMessage = success ? "Scan recovered successfully" : "Recovery failed"
                    if !success {
                        self?.handleScanningFailure(error: ScanningError.recoveryFailed)
                    }
                }
            }
        )
    }
    
    private func setupSystemMonitoring() {
        systemMonitor = ScanningSystemMonitor { [weak self] status in
            self?.handleSystemStatusUpdate(status)
        }
    }
    
    private func setupAutosave() {
        // Autosave every 30 seconds if we have enough data
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.autosaveSession()
        }
    }
    
    private func setupEnvironmentValidation() {
        environmentValidator = EnvironmentValidator { [weak self] conditions in
            DispatchQueue.main.async {
                self?.environmentConditions = conditions
                self?.isEnvironmentValid = conditions.allSatisfy { $0.isAcceptable }
                
                // Update guidance based on environment conditions
                if let worstCondition = conditions
                    .filter({ !$0.isAcceptable })
                    .min(by: { $0.score < $1.score }) {
                    self?.guidanceMessage = worstCondition.recommendation
                }
            }
        }
    }
    
    private func setupMotionBlurCompensation() {
        motionBlurCompensator = MotionBlurCompensator { [weak self] blurAmount in
            DispatchQueue.main.async {
                self?.handleBlurDetected(blurAmount)
            }
        }
    }
    
    private func setupErrorHandling() {
        errorHandler.onErrorOccurred = { [weak self] error in
            DispatchQueue.main.async {
                self?.handleErrorOccurred(error)
            }
        }
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor = ScanningPerformanceMonitor { [weak self] metrics in
            DispatchQueue.main.async {
                self?.handlePerformanceUpdate(metrics)
            }
        }
    }
    
    private func setupOptimizationGuide() {
        optimizationGuide = ScanningOptimizationGuide { [weak self] hint in
            DispatchQueue.main.async {
                self?.handleOptimizationHint(hint)
            }
        }
    }
    
    private func setupSpeedController() {
        speedController = AdaptiveScanningSpeedController { [weak self] speed, guidance in
            DispatchQueue.main.async {
                self?.handleSpeedUpdate(speed, guidance: guidance)
            }
        }
    }
    
    private func setupPreviewViewModel() {
        previewViewModel = ScanningPreviewViewModel(scanningFeature: self)
    }
    
    private func handleOptimizationHint(_ hint: OptimizationHint) {
        if !currentHints.contains(where: { $0.title == hint.title }) {
            currentHints.append(hint)
            
            if currentHints.count > 5 {
                currentHints.removeFirst()
            }
            
            if hint.priority >= 4 && preferences.isHapticFeedbackEnabled {
                hapticManager.playError()
            }
            
            if preferences.isVoiceFeedbackEnabled {
                voiceFeedback.speakGuidance(hint.description)
            }
            
            guideMessage = hint.description
        }
    }
    
    private func handleSpeedUpdate(_ speed: Float, guidance: String) {
        currentSpeed = speed
        speedGuidance = guidance
        
        if preferences.isHapticFeedbackEnabled {
            if speed > optimizedSpeed * 1.2 {
                hapticManager.playError()
            } else if speed < optimizedSpeed * 0.8 {
                hapticManager.playProgressFeedback(0.5)
            }
        }
        
        if preferences.isSpatialAudioEnabled && speed > optimizedSpeed * 1.2 {
            spatialAudio.playQualityAlert(severity: min(speed - optimizedSpeed, 1.0))
        }
        
        if abs(speed - optimizedSpeed) > 0.2 {
            guideMessage = guidance
        }
    }
    
    public func updatePreferences(_ newPreferences: ScanningPreferences) {
        preferences = newPreferences
        
        // Update feedback systems
        spatialAudio.setEnabled(preferences.isSpatialAudioEnabled)
        dynamicAudio.setScannerSoundEnabled(preferences.isScannerSoundEnabled)
        voiceFeedback.setEnabled(preferences.isVoiceFeedbackEnabled)
        hapticManager.setIntensity(preferences.hapticIntensity)
        
        showingScanningGuide = preferences.isVisualGuideEnabled
    }
    
    private func provideFeedback(frame: ARFrame) {
        let currentTime = CACurrentMediaTime()
        
        // Update scanning speed
        speedController?.updateSpeed(
            frame: frame,
            quality: scanningQuality,
            coverage: scanCoverage
        )
        
        // Update optimization guidance
        if let points = capturedPoints {
            optimizationGuide?.analyzeScanningSession(
                frame: frame,
                quality: scanningQuality,
                coverage: scanCoverage,
                points: points
            )
        }
        
        // Update audio feedback
        if preferences.isSpatialAudioEnabled && 
           currentTime - lastAudioUpdate >= audioUpdateInterval {
            updateSpatialAudioFeedback(frame: frame)
            lastAudioUpdate = currentTime
        }
        
        // Update voice guidance
        if preferences.isVoiceFeedbackEnabled && 
           currentTime - lastGuidanceTime >= preferences.guidanceUpdateInterval {
            voiceFeedback.speakGuidance(guideMessage)
            lastGuidanceTime = currentTime
        }
        
        // Update haptic feedback
        if preferences.isHapticFeedbackEnabled {
            hapticManager.updateContinuousFeedback(
                intensity: scanningQuality * preferences.hapticIntensity,
                sharpness: scanCoverage
            )
        }
    }
    
    private func updateSpatialAudioFeedback(frame: ARFrame) {
        let camera = frame.camera
        let position = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        
        spatialAudio.updateScanningFeedback(
            position: position,
            speed: currentSpeed,
            quality: scanningQuality
        )
        
        lastPosition = position
    }
    
    private func handlePerformanceUpdate(_ metrics: ScanningMetrics) {
        currentMetrics = metrics
        isPerformanceOptimal = metrics.isPerformanceAcceptable
        
        if !metrics.isPerformanceAcceptable {
            // Provide haptic warning for performance issues
            hapticManager.playError()
            adjustForPerformance(metrics)
        }
        
        // Update haptic feedback based on performance
        hapticManager.updateContinuousFeedback(
            intensity: metrics.isPerformanceAcceptable ? 0.5 : 0.8,
            sharpness: Float(metrics.fps / 60.0)
        )
        
        // Adjust scanning parameters based on performance
        if !metrics.isPerformanceAcceptable {
            adjustForPerformance(metrics)
        }
        
        // Update UI if performance is significantly impaired
        if metrics.fps < 20 || metrics.thermalState == .critical {
            handlePerformanceCritical(metrics)
        }
    }
    
    private func adjustForPerformance(_ metrics: ScanningMetrics) {
        if metrics.cpuUsage > 0.9 || metrics.memoryUsage > 0.8 {
            // Reduce processing quality
            pointCloudOptimizer.setOptimizationLevel(.aggressive)
            visualizationController?.setQualityLevel(.low)
        }
        
        if metrics.thermalState == .serious {
            // Reduce update frequency
            sessionDelegate?.setUpdateInterval(0.5)
        }
        
        if metrics.batteryLevel < 0.2 {
            // Enable power saving mode
            visualizationController?.setQualityLevel(.minimum)
            sessionDelegate?.setUpdateInterval(1.0)
        }
    }
    
    private func handlePerformanceCritical(_ metrics: ScanningMetrics) {
        if metrics.thermalState == .critical {
            let error = ScanningError(
                type: .systemResources,
                message: "Device temperature critical",
                recommendation: "Please allow device to cool down",
                canRetry: false,
                recoveryAction: nil
            )
            handleErrorOccurred(error)
        }
        
        if metrics.fps < 10 {
            pauseScanningIfNeeded()
            guidanceMessage = "Performance too low, try closing background apps"
        }
    }
    
    private func handleBlurDetected(_ blurAmount: Float) {
        currentBlurAmount = blurAmount
        isCompensatingBlur = blurAmount > 0.3
        
        if isCompensatingBlur {
            hapticManager.playQualityFeedback(1.0 - blurAmount)
            voiceFeedback.speakGuidance("Hold device more steady")
        }
    }
    
    private func autosaveSession() {
        guard scanningState == .scanning,
              let points = capturedPoints,
              !points.isEmpty else {
            return
        }
        
        let sessionId = currentSessionId ?? UUID()
        currentSessionId = sessionId
        
        let session = ScanSession(
            id: sessionId,
            timestamp: Date(),
            points: points,
            quality: scanningQuality,
            metadata: getCurrentSessionMetadata()
        )
        
        do {
            try sessionStorage.saveSession(session)
        } catch {
            print("Failed to autosave session: \(error)")
        }
    }
    
    private func getCurrentSessionMetadata() -> [String: String] {
        [
            "camera": selectedCamera?.rawValue ?? "unknown",
            "scanningMode": currentMode?.rawValue ?? "unknown",
            "deviceType": UIDevice.current.model
        ]
    }
    
    private func handleSystemStatusUpdate(_ status: SystemStatus) {
        systemStatus = status
        
        switch status {
        case .optimal:
            break
        case .warning(let message):
            guidanceMessage = message
            hapticManager.playQualityFeedback(0.5)
            voiceFeedback.speakGuidance(message)
        case .critical(let message):
            guidanceMessage = message
            hapticManager.playCaptureFailed()
            voiceFeedback.speakGuidance(message)
            pauseScanningIfNeeded()
        }
    }
    
    private func pauseScanningIfNeeded() {
        if case .critical = systemStatus {
            stopScanning()
            scanningState = .error(ScanningError.systemResourcesUnavailable)
        }
    }
    
    public func selectCamera(_ camera: ScanningCamera) {
        guard scanningCapabilities.availableCameras.contains(camera) else {
            return
        }
        selectedCamera = camera
    }
    
    public func startScanning() {
        guard isEnvironmentValid else {
            guidanceMessage = "Please address environment issues before scanning"
            hapticManager.playError()
            voiceFeedback.speakGuidance(guidanceMessage)
            return
        }
        
        scanningState = .scanning
        hapticManager.startContinuousFeedback()
        spatialAudio.startContinuousFeedback()
        
        guard let camera = selectedCamera,
              let session = arSession else {
            return
        }
        
        // Configure scanning based on selected camera
        switch camera {
        case .front:
            configureFrontCameraScanning(session)
        case .back:
            configureBackCameraScanning(session)
        }
    }
    
    private func configureFrontCameraScanning(_ session: ARSession) {
        guard capabilityChecker.hasTrueDepth else { 
            scanningState = .error(ScanningError.deviceNotSupported)
            return 
        }
        
        let configuration = ARFaceTrackingConfiguration()
        
        // Configure TrueDepth specific settings
        if #available(iOS 13.0, *) {
            configuration.maximumNumberOfTrackedFaces = 1
        }
        
        // Reset quality monitoring
        scanningQuality = 0.0
        guidanceMessage = "Position your face in the frame"
        
        // Start the session with face tracking configuration
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        scanningState = .scanning
    }
    
    private func configureBackCameraScanning(_ session: ARSession) {
        guard capabilityChecker.hasLiDAR else {
            scanningState = .error(ScanningError.deviceNotSupported)
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        
        // Configure LiDAR specific settings
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        // Reset quality monitoring
        scanningQuality = 0.0
        guidanceMessage = "Move around to capture the surface"
        
        // Start the session with LiDAR configuration
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        scanningState = .scanning
    }
    
    private func handleScanningFailure(error: Error) {
        Task {
            if await recoveryManager.canAttemptRecovery() {
                if await recoveryManager.attemptRecovery() {
                    // Restore from cache
                    if let (points, quality) = cacheManager.restoreFromLastCheckpoint() {
                        capturedPoints = points
                        scanningQuality = quality
                        return
                    }
                }
            }
            
            hapticManager.playCaptureFailed()
            voiceFeedback.speakGuidance("Scanning failed. Please try again.")
            scanningState = .error(error)
        }
    }
    
    public func stopScanning() {
        hapticManager.stopContinuousFeedback()
        spatialAudio.stopContinuousFeedback()
        arSession?.pause()
        scanningState = .idle
        guidanceMessage = ""
        voiceFeedback.stop()
        lastPosition = nil
        cacheManager.clear()
        recoveryManager.reset()
    }
    
    public func capture() async throws -> Data {
        guard scanningQuality >= 0.7 else {
            hapticManager.playCaptureFailed()
            throw ScanningQualityError.qualityBelowThreshold
        }
        
        guard coverageTracker.isCoverageComplete() else {
            hapticManager.playCaptureFailed()
            throw ScanningQualityError.insufficientCoverage
        }
        
        do {
            let result = try await performCapture()
            hapticManager.playCaptureSuccess()
            coverageTracker.reset()
            return result
        } catch {
            hapticManager.playCaptureFailed()
            throw error
        }
    }
    
    private func performCapture() async throws -> Data {
        // Move existing capture logic here
        scanningState = .processing
        captureProgressManager.reset()
        
        guard let meshProcessor = meshProcessor else {
            throw MeshProcessingError.processingFailed
        }
        
        captureProgressManager.updateStage(.processingDepthData)
        
        captureProgressManager.updateStage(.generatingMesh)
        let mesh = try meshProcessor.generateMesh(from: capturedPoints)
        
        captureProgressManager.updateStage(.optimizingMesh)
        // Optimization would happen here if needed
        
        captureProgressManager.updateStage(.preparingExport)
        let exportedData = try meshProcessor.exportMesh(mesh, format: .usdz)
        
        captureProgressManager.updateStage(.complete)
        scanningState = .complete
        
        return exportedData
    }
    
    public func resumeSession(_ session: ScanSession) async {
        isResumingSession = true
        guidanceMessage = "Resuming previous scan..."
        
        do {
            currentSessionId = session.id
            capturedPoints = session.points
            scanningQuality = session.quality
            
            // Update cache and recovery state
            cacheManager.cachePoints(session.points, quality: session.quality)
            recoveryManager.saveState(session.points, quality: session.quality)
            
            // Start scanning from last known state
            startScanning()
            
            isResumingSession = false
            guidanceMessage = "Scan resumed successfully"
        } catch {
            isResumingSession = false
            handleScanningFailure(error: error)
        }
    }
    
    public func deleteSession(_ session: ScanSession) {
        do {
            try sessionStorage.deleteSession(id: session.id)
            availableSessions = try sessionStorage.listSessions()
        } catch {
            print("Failed to delete session: \(error)")
        }
    }
    
    public func cleanupOldSessions() {
        do {
            try sessionStorage.cleanupOldSessions()
            availableSessions = try sessionStorage.listSessions()
        } catch {
            print("Failed to cleanup old sessions: \(error)")
        }
    }
    
    private func processNewPoints(_ points: [Point3D]) {
        optimizationQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isOptimizing = true
            
            // Process points and update state
            let startTime = CACurrentMediaTime()
            var processedPoints = points
            
            if self.isCompensatingBlur,
               let compensator = self.motionBlurCompensator {
                processedPoints = compensator.compensateForBlur(
                    points,
                    blurAmount: self.currentBlurAmount
                )
            }
            
            // Update coverage and feedback
            let coverage = self.coverageTracker.updateCoverage(with: processedPoints)
            let heatmap = self.coverageTracker.getCoverageHeatmap()
            let optimizedPoints = self.pointCloudOptimizer.optimizePointCloud(processedPoints)
            
            let processingTime = CACurrentMediaTime() - startTime
            self.performanceMonitor?.recordProcessingTime(processingTime)
            
            DispatchQueue.main.async {
                self.updateScanningState(
                    coverage: coverage,
                    points: optimizedPoints,
                    processingTime: processingTime
                )
            }
        }
    }
    
    private func updateScanningState(
        coverage: Float,
        points: [Point3D],
        processingTime: TimeInterval
    ) {
        // Update state
        self.scanCoverage = coverage
        self.coverageHeatmap = coverageTracker.getCoverageHeatmap()
        self.capturedPoints = points
        
        // Update visualization
        updateVisualization(mode: visualizationMode)
        
        // Provide feedback based on scanning quality
        provideScanningFeedback(coverage: coverage)
        
        // Update optimization hints if needed
        updateOptimizationHints()
        
        self.isOptimizing = false
    }
    
    private func updateScanningFeedback(_ frame: ARFrame) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastAudioUpdate >= audioUpdateInterval else { return }
        
        // Calculate current position
        let camera = frame.camera
        let position = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        
        // Calculate speed if we have a previous position
        var speed: Float = 0
        if let lastPos = lastPosition {
            let displacement = position - lastPos
            speed = length(displacement) / Float(audioUpdateInterval)
        }
        
        // Update audio feedback
        spatialAudio.updateScanningFeedback(
            position: position,
            speed: speed,
            quality: scanningQuality
        )
        
        lastPosition = position
        lastAudioUpdate = currentTime
    }
    
    private func provideScanningFeedback(coverage: Float) {
        // Only provide feedback if enabled
        if preferences.isHapticFeedbackEnabled {
            hapticManager.updateContinuousFeedback(
                intensity: scanningQuality * preferences.hapticIntensity,
                sharpness: coverage
            )
        }
        
        if preferences.isVoiceFeedbackEnabled {
            // Update guidance based on user interval preference
            let currentTime = CACurrentMediaTime()
            if currentTime - lastGuidanceTime >= preferences.guidanceUpdateInterval {
                voiceFeedback.speakGuidance(guidanceMessage)
                lastGuidanceTime = currentTime
            }
        }
        
        // Provide spatial audio feedback if enabled
        if preferences.isSpatialAudioEnabled {
            updateSpatialAudioFeedback(coverage: coverage)
        }
        
        // Update visual guidance
        if preferences.isVisualGuideEnabled {
            updateVisualGuidance(coverage: coverage)
        }
    }
    
    private func validateScanningQuality() -> Bool {
        let qualityMeetsThreshold = scanningQuality >= preferences.minimumQualityThreshold
        let coverageMeetsThreshold = scanCoverage >= preferences.minimumCoverageThreshold
        
        return qualityMeetsThreshold && coverageMeetsThreshold
    }
    
    public func toggleFeature(_ feature: ScanningFeature) {
        switch feature {
        case .metrics:
            preferences.showQualityMetrics.toggle()
            showingMetrics.toggle()
        case .speedGauge:
            preferences.showSpeedGauge.toggle()
            showingSpeedGauge.toggle()
        case .coverageMap:
            preferences.showCoverageMap.toggle()
            showingCoverageMap.toggle()
        }
        preferences.savePreferences()
    }
    
    public enum ScanningFeature {
        case metrics
        case speedGauge
        case coverageMap
    }
    
    private func updateSpatialAudioFeedback(coverage: Float) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastAudioCueTime >= audioCueCooldown else { return }
        
        // Find areas needing attention
        if let uncoveredRegion = findLargestUncoveredRegion() {
            spatialAudio.playCoverageAlert(
                missingArea: uncoveredRegion,
                urgency: 1.0 - coverage
            )
            lastAudioCueTime = currentTime
        }
        
        // Quality feedback
        if scanningQuality < 0.5 {
            spatialAudio.playQualityAlert(severity: 1.0 - scanningQuality)
            lastAudioCueTime = currentTime
        }
        
        // Movement guidance
        if let direction = determineOptimalScanDirection() {
            spatialAudio.playDirectionalCue(
                direction: direction,
                intensity: 0.7
            )
            lastAudioCueTime = currentTime
        }
        
        // Completion sound
        if coverage >= 0.9 && scanningQuality >= 0.8 {
            spatialAudio.playCompletionSound()
        }
    }
    
    private func findLargestUncoveredRegion() -> SIMD3<Float>? {
        // Analyze coverage heatmap
        if let lowestCoverage = coverageHeatmap
            .min(by: { $0.density < $1.density }) {
            return lowestCoverage.position
        }
        return nil
    }
    
    private func determineOptimalScanDirection() -> SpatialAudioFeedback.ScanDirection? {
        guard let currentPoints = capturedPoints,
              !currentPoints.isEmpty else {
            return .forward
        }
        
        // Analyze point distribution and suggest optimal direction
        let boundingBox = calculateBoundingBox(currentPoints)
        let center = (boundingBox.max + boundingBox.min) * 0.5
        
        if let lowestCoverage = coverageHeatmap
            .min(by: { $0.density < $1.density }) {
            let direction = lowestCoverage.position - center
            
            // Determine primary direction based on largest component
            let absDirection = abs(direction)
            if absDirection.x > absDirection.y && absDirection.x > absDirection.z {
                return direction.x > 0 ? .right : .left
            } else if absDirection.y > absDirection.x && absDirection.y > absDirection.z {
                return direction.y > 0 ? .up : .down
            } else {
                return direction.z > 0 ? .backward : .forward
            }
        }
        
        return nil
    }
    
    private func calculateBoundingBox(_ points: [Point3D]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var min = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        var max = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
        
        for point in points {
            let p = SIMD3<Float>(point.x, point.y, point.z)
            min = simd_min(min, p)
            max = simd_max(max, p)
        }
        
        return (min, max)
    }
    
    public func setSpatialAudioEnabled(_ enabled: Bool) {
        spatialAudio.setEnabled(enabled)
    }
    
    private func updateOptimizationHints() {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastHintTime >= hintCooldown else { return }
        
        // Filter out old hints
        currentHints = currentHints.filter { hint in
            switch hint.priority {
            case 5: return true // Always show critical hints
            case 4: return currentTime - lastHintTime < 10
            case 3: return currentTime - lastHintTime < 5
            default: return false
            }
        }
        
        // Update last hint time if we have active hints
        if !currentHints.isEmpty {
            lastHintTime = currentTime
        }
    }
    
    public func toggleScanningGuide() {
        showingScanningGuide.toggle()
        preferences.isVisualGuideEnabled = showingScanningGuide
        preferences.savePreferences()
        
        if showingScanningGuide {
            hapticManager.playProgressFeedback(0.5)
            voiceFeedback.speakGuidance("Scanning guide enabled")
        }
    }
    
    public func resetScanning() {
        coverageTracker.reset()
        scanCoverage = 0
        coverageHeatmap = []
        capturedPoints = []
        scanningQuality = 0
        scanningState = .idle
        guidanceMessage = ""
    }
    
    private func handleErrorOccurred(_ error: ScanningError) {
        currentError = error
        hapticManager.playError()
        voiceFeedback.speakGuidance(error.message)
        
        switch error.type {
        case .qualityLow:
            pauseScanningIfNeeded()
        case .insufficientCoverage:
            updateGuidanceForCoverage()
        case .motionBlur:
            handleMotionBlurError()
        case .systemResources:
            handleSystemResourceError()
        case .tracking:
            handleTrackingError()
        default:
            break
        }
    }
    
    private func handleMotionBlurError() {
        isCompensatingBlur = true
        guidanceMessage = "Hold device steady to reduce motion blur"
    }
    
    private func handleSystemResourceError() {
        stopScanning()
        scanningState = .error(currentError!)
    }
    
    private func handleTrackingError() {
        pauseScanningIfNeeded()
        guidanceMessage = "Move device slowly to regain tracking"
    }
    
    private func updateGuidanceForCoverage() {
        let uncoveredRegions = findUncoveredRegions()
        if !uncoveredRegions.isEmpty {
            guidanceMessage = "Scan missing areas: \(uncoveredRegions.joined(separator: ", "))"
        }
    }
    
    private func findUncoveredRegions() -> [String] {
        var regions: [String] = []
        
        // Analyze coverage heatmap to identify areas needing attention
        let lowCoveragePoints = coverageHeatmap.filter { $0.density < 0.3 }
        
        if !lowCoveragePoints.isEmpty {
            // Group points by general region
            let groups = groupPointsByRegion(lowCoveragePoints)
            regions = groups.map { describeScanRegion($0) }
        }
        
        return regions
    }
    
    private func groupPointsByRegion(_ points: [(position: SIMD3<Float>, density: Float)]) -> [SIMD3<Float>] {
        // Simple clustering to group nearby points
        var groups: [SIMD3<Float>] = []
        let threshold: Float = 0.1 // 10cm clustering threshold
        
        for point in points {
            if let nearestGroup = groups.first(where: { distance($0, point.position) < threshold }) {
                // Update group center
                let index = groups.firstIndex(of: nearestGroup)!
                groups[index] = (nearestGroup + point.position) * 0.5
            } else {
                groups.append(point.position)
            }
        }
        
        return groups
    }
    
    private func describeScanRegion(_ position: SIMD3<Float>) -> String {
        // Convert position to user-friendly description
        if position.y > 0.3 {
            return "upper area"
        } else if position.y < -0.3 {
            return "lower area"
        } else if position.x > 0.3 {
            return "right side"
        } else if position.x < -0.3 {
            return "left side"
        } else if position.z > 0.3 {
            return "back"
        } else {
            return "front"
        }
    }
    
    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        length(a - b)
    }
    
    public func retryScanning() {
        guard currentError?.canRetry == true else { return }
        
        isRetrying = true
        errorHandler.resetRetryCount()
        
        // Reset necessary state
        currentError = nil
        isCompensatingBlur = false
        
        // Restart scanning with existing data
        startScanning()
        
        isRetrying = false
    }
    
    public func dismissError() {
        currentError = nil
    }
    
    public func clearHints() {
        currentHints.removeAll()
    }
    
    private func handleSpeedUpdate(_ speed: Float, guidance: String) {
        currentSpeed = speed
        speedGuidance = guidance
        
        // Update haptic feedback based on speed
        if speed > 0.8 {
            hapticManager.playError()
        } else if speed < 0.3 {
            hapticManager.playProgressFeedback(0.5)
        }
        
        // Provide spatial audio feedback for speed
        if speed > 1.0 {
            spatialAudio.playQualityAlert(severity: min(speed - 1.0, 1.0))
        }
        
        // Update guidance message if speed is suboptimal
        if speed > 1.2 || speed < 0.5 {
            guidanceMessage = guidance
        }
    }
}

public enum ScanningState {
    case idle
    case scanning
    case processing
    case complete
    case error(Error)
}

public enum ScanningError: Error {
    case deviceNotSupported
    case scanningFailed
    case processingFailed
    case recoveryFailed
    case systemResourcesUnavailable
}
