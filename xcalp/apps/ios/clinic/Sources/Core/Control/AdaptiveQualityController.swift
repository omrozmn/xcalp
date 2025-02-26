import ARKit
import Metal
import Combine
import os.log

final class AdaptiveQualityController {
    static let shared = AdaptiveQualityController()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "AdaptiveQuality")
    private let analyzer = ScanningQualityAnalyzer.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    private var qualitySubscription: AnyCancellable?
    private var adaptationHistory: RingBuffer<AdaptationEvent>
    private let adaptationQueue = DispatchQueue(label: "com.xcalp.quality.adaptation", qos: .userInteractive)
    
    private var currentSettings = QualitySettings()
    private var lastAdaptation = Date()
    private let minimumAdaptationInterval: TimeInterval = 0.5
    
    // Control parameters
    private let lightingThresholdRange = 0.3...1.0
    private let motionThresholdRange = 0.5...0.95
    private let featureQualityRange = 0.6...0.95
    private let depthAccuracyRange = 0.7...0.98
    
    private init() {
        self.adaptationHistory = RingBuffer(capacity: 100)
        setupQualityMonitoring()
    }
    
    struct AdaptationEvent: Codable {
        let timestamp: Date
        let previousSettings: QualitySettings
        let newSettings: QualitySettings
        let metrics: QualityMetrics
        let reason: AdaptationReason
    }
    
    enum AdaptationReason: String, Codable {
        case qualityImprovement
        case performanceOptimization
        case errorRecovery
        case userRequest
        case thermalMitigation
    }
    
    // MARK: - Public Methods
    
    func startAdaptiveControl() {
        qualitySubscription = NotificationCenter.default.publisher(
            for: .qualityIssuesDetected
        )
        .throttle(
            for: .seconds(minimumAdaptationInterval),
            scheduler: adaptationQueue,
            latest: true
        )
        .sink { [weak self] notification in
            guard let analysis = notification.userInfo?["analysis"] as? QualityAnalysis else {
                return
            }
            self?.handleQualityIssues(analysis)
        }
        
        logger.info("Started adaptive quality control")
    }
    
    func stopAdaptiveControl() {
        qualitySubscription?.cancel()
        qualitySubscription = nil
        logger.info("Stopped adaptive quality control")
    }
    
    func forceQualityUpdate(
        to settings: QualitySettings,
        reason: AdaptationReason
    ) {
        adaptationQueue.async { [weak self] in
            self?.applyQualitySettings(
                settings,
                reason: reason,
                force: true
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func handleQualityIssues(_ analysis: QualityAnalysis) {
        guard Date().timeIntervalSince(lastAdaptation) >= minimumAdaptationInterval else {
            return
        }
        
        // Generate adaptive settings based on quality analysis
        let newSettings = generateAdaptiveSettings(
            from: analysis,
            current: currentSettings
        )
        
        // Apply new settings if they represent a significant change
        if shouldUpdateSettings(from: currentSettings, to: newSettings) {
            applyQualitySettings(
                newSettings,
                reason: .qualityImprovement,
                force: false
            )
        }
    }
    
    private func generateAdaptiveSettings(
        from analysis: QualityAnalysis,
        current: QualitySettings
    ) -> QualitySettings {
        var settings = current
        
        // Adjust lighting threshold
        if analysis.metrics.lightingQuality < ClinicalConstants.minimumLightingQuality {
            settings.lightingThreshold = max(
                lightingThresholdRange.lowerBound,
                current.lightingThreshold * 0.9
            )
        } else {
            settings.lightingThreshold = min(
                lightingThresholdRange.upperBound,
                current.lightingThreshold * 1.1
            )
        }
        
        // Adjust motion threshold
        if analysis.metrics.motionStability < ClinicalConstants.minimumMotionStability {
            settings.motionThreshold = max(
                motionThresholdRange.lowerBound,
                current.motionThreshold * 0.95
            )
        } else {
            settings.motionThreshold = min(
                motionThresholdRange.upperBound,
                current.motionThreshold * 1.05
            )
        }
        
        // Adjust feature quality requirements
        if analysis.metrics.featureQuality < ClinicalConstants.minFeatureMatchConfidence {
            settings.featureQualityThreshold = max(
                featureQualityRange.lowerBound,
                current.featureQualityThreshold * 0.9
            )
        } else {
            settings.featureQualityThreshold = min(
                featureQualityRange.upperBound,
                current.featureQualityThreshold * 1.1
            )
        }
        
        // Adjust processing quality based on performance
        let metrics = performanceMonitor.getCurrentMetrics()
        if metrics.cpuUsage > 80 || metrics.memoryUsage > 150_000_000 {
            settings.processingQuality = .medium
        } else if metrics.cpuUsage < 50 && metrics.memoryUsage < 100_000_000 {
            settings.processingQuality = .high
        }
        
        return settings
    }
    
    private func shouldUpdateSettings(
        from current: QualitySettings,
        to new: QualitySettings
    ) -> Bool {
        let thresholdChange = abs(
            current.lightingThreshold - new.lightingThreshold
        ) / current.lightingThreshold > 0.1
        
        let motionChange = abs(
            current.motionThreshold - new.motionThreshold
        ) / current.motionThreshold > 0.1
        
        let qualityChange = current.processingQuality != new.processingQuality
        
        let featureChange = abs(
            current.featureQualityThreshold - new.featureQualityThreshold
        ) / current.featureQualityThreshold > 0.1
        
        return thresholdChange || motionChange || qualityChange || featureChange
    }
    
    private func applyQualitySettings(
        _ settings: QualitySettings,
        reason: AdaptationReason,
        force: Bool
    ) {
        // Skip if changes are too frequent unless forced
        if !force && Date().timeIntervalSince(lastAdaptation) < minimumAdaptationInterval {
            return
        }
        
        let event = AdaptationEvent(
            timestamp: Date(),
            previousSettings: currentSettings,
            newSettings: settings,
            metrics: analyzer.getCurrentMetrics(),
            reason: reason
        )
        
        // Update current settings
        currentSettings = settings
        lastAdaptation = Date()
        
        // Record adaptation event
        adaptationHistory.append(event)
        
        // Notify observers
        NotificationCenter.default.post(
            name: .qualitySettingsDidChange,
            object: self,
            userInfo: [
                "settings": settings,
                "reason": reason,
                "event": event
            ]
        )
        
        // Log change
        logger.info("""
            Quality settings adapted:
            - Reason: \(reason)
            - Lighting threshold: \(settings.lightingThreshold)
            - Motion threshold: \(settings.motionThreshold)
            - Feature quality: \(settings.featureQualityThreshold)
            - Processing quality: \(settings.processingQuality)
            """)
    }
    
    private func setupQualityMonitoring() {
        // Monitor thermal state
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        
        // Monitor memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleThermalStateChange(_ notification: Notification) {
        guard let processInfo = notification.object as? ProcessInfo else { return }
        
        switch processInfo.thermalState {
        case .serious, .critical:
            let settings = QualitySettings(
                lightingThreshold: lightingThresholdRange.lowerBound,
                motionThreshold: motionThresholdRange.lowerBound,
                featureQualityThreshold: featureQualityRange.lowerBound,
                processingQuality: .low
            )
            forceQualityUpdate(to: settings, reason: .thermalMitigation)
            
        case .nominal:
            // Gradually restore settings if thermal state improves
            let settings = QualitySettings(
                lightingThreshold: (lightingThresholdRange.lowerBound + lightingThresholdRange.upperBound) / 2,
                motionThreshold: (motionThresholdRange.lowerBound + motionThresholdRange.upperBound) / 2,
                featureQualityThreshold: (featureQualityRange.lowerBound + featureQualityRange.upperBound) / 2,
                processingQuality: .medium
            )
            forceQualityUpdate(to: settings, reason: .thermalMitigation)
            
        default:
            break
        }
    }
    
    @objc private func handleMemoryWarning(_ notification: Notification) {
        let settings = QualitySettings(
            lightingThreshold: currentSettings.lightingThreshold,
            motionThreshold: currentSettings.motionThreshold,
            featureQualityThreshold: currentSettings.featureQualityThreshold,
            processingQuality: .low
        )
        forceQualityUpdate(to: settings, reason: .performanceOptimization)
    }
}

// MARK: - Supporting Types

extension AdaptiveQualityController {
    struct QualitySettings: Codable {
        var lightingThreshold: Float
        var motionThreshold: Float
        var featureQualityThreshold: Float
        var processingQuality: ProcessingQuality
        
        enum ProcessingQuality: Int, Codable {
            case low = 0
            case medium = 1
            case high = 2
        }
        
        init(
            lightingThreshold: Float = 0.7,
            motionThreshold: Float = 0.8,
            featureQualityThreshold: Float = 0.85,
            processingQuality: ProcessingQuality = .high
        ) {
            self.lightingThreshold = lightingThreshold
            self.motionThreshold = motionThreshold
            self.featureQualityThreshold = featureQualityThreshold
            self.processingQuality = processingQuality
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let qualitySettingsDidChange = Notification.Name("qualitySettingsDidChange")
}