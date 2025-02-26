import Foundation
import ARKit
import Metal

public actor AdaptiveQualityManager {
    public static let shared = AdaptiveQualityManager()
    
    private let performanceMonitor: ScanPerformanceMonitor
    private let thermalManager: ThermalManager
    private let analytics: AnalyticsService
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "AdaptiveQuality")
    
    private var currentProfile: QualityProfile
    private var adaptiveSettings: AdaptiveSettings
    private var qualityHistory: [QualityAdjustment] = []
    private let historyLimit = 50
    
    private init(
        performanceMonitor: ScanPerformanceMonitor = .shared,
        thermalManager: ThermalManager = .shared,
        analytics: AnalyticsService = .shared
    ) {
        self.performanceMonitor = performanceMonitor
        self.thermalManager = thermalManager
        self.analytics = analytics
        
        self.currentProfile = QualityProfile.balanced
        self.adaptiveSettings = AdaptiveSettings()
        
        setupQualityMonitoring()
    }
    
    public func getCurrentProfile() -> QualityProfile {
        return currentProfile
    }
    
    public func setInitialProfile(_ profile: QualityProfile) async {
        currentProfile = profile
        await applyProfile(profile)
        
        analytics.track(
            event: .qualityProfileChanged,
            properties: ["profile": profile.rawValue]
        )
    }
    
    public func updateQualitySettings(
        performance: PerformanceMetrics,
        environment: EnvironmentMetrics
    ) async {
        let adjustment = determineQualityAdjustment(
            performance: performance,
            environment: environment
        )
        
        if let newProfile = adjustment.profile, newProfile != currentProfile {
            await handleProfileTransition(to: newProfile, reason: adjustment.reason)
        }
        
        // Apply specific adjustments
        await applyParameterAdjustments(adjustment.parameters)
        
        // Record adjustment
        recordQualityAdjustment(adjustment)
    }
    
    public func getQualityHistory() -> [QualityAdjustment] {
        return qualityHistory
    }
    
    private func determineQualityAdjustment(
        performance: PerformanceMetrics,
        environment: EnvironmentMetrics
    ) -> QualityAdjustment {
        var parameters: [QualityParameter] = []
        var reason: AdjustmentReason = .performance
        var targetProfile: QualityProfile?
        
        // Check thermal state
        if performance.thermalState == .critical {
            targetProfile = .minimum
            reason = .thermal
        }
        // Check performance metrics
        else if performance.frameProcessingTime > adaptiveSettings.maxFrameTime {
            parameters.append(.reduceResolution)
            parameters.append(.reduceMeshDetail)
            reason = .performance
        }
        // Check environment
        else if environment.lightIntensity < adaptiveSettings.minLightIntensity {
            parameters.append(.increaseLightSensitivity)
            reason = .environment
        }
        
        // Check memory usage
        if performance.systemMetrics.memoryUsage > adaptiveSettings.maxMemoryUsage {
            if targetProfile == nil {
                targetProfile = .reduced
            }
            parameters.append(.reduceTextureQuality)
        }
        
        return QualityAdjustment(
            timestamp: Date(),
            profile: targetProfile,
            parameters: parameters,
            reason: reason,
            metrics: QualityMetrics(
                performance: performance,
                environment: environment
            )
        )
    }
    
    private func handleProfileTransition(
        to newProfile: QualityProfile,
        reason: AdjustmentReason
    ) async {
        let oldProfile = currentProfile
        currentProfile = newProfile
        
        // Apply new profile
        await applyProfile(newProfile)
        
        // Log transition
        logger.info("Quality profile transition: \(oldProfile) -> \(newProfile) (\(reason))")
        
        analytics.track(
            event: .qualityProfileTransition,
            properties: [
                "oldProfile": oldProfile.rawValue,
                "newProfile": newProfile.rawValue,
                "reason": reason.rawValue
            ]
        )
        
        // Notify observers
        NotificationCenter.default.post(
            name: .qualityProfileChanged,
            object: nil,
            userInfo: [
                "oldProfile": oldProfile,
                "newProfile": newProfile,
                "reason": reason
            ]
        )
    }
    
    private func applyProfile(_ profile: QualityProfile) async {
        // Configure AR session
        await ARConfiguration.shared.configureForQuality(profile)
        
        // Configure Metal settings
        await MetalConfiguration.shared.configureForQuality(profile)
        
        // Configure scanning parameters
        ScanningConfiguration.shared.quality = profile.scanningQuality
    }
    
    private func applyParameterAdjustments(_ parameters: [QualityParameter]) async {
        for parameter in parameters {
            switch parameter {
            case .reduceResolution:
                await adjustResolution(decrease: true)
            case .reduceMeshDetail:
                await adjustMeshDetail(decrease: true)
            case .reduceTextureQuality:
                await adjustTextureQuality(decrease: true)
            case .increaseLightSensitivity:
                await adjustLightSensitivity(increase: true)
            }
        }
    }
    
    private func recordQualityAdjustment(_ adjustment: QualityAdjustment) {
        qualityHistory.append(adjustment)
        
        if qualityHistory.count > historyLimit {
            qualityHistory.removeFirst()
        }
    }
    
    private func setupQualityMonitoring() {
        Task {
            for await metrics in await performanceMonitor.getPerformanceStream() {
                let environment = await getEnvironmentMetrics()
                await updateQualitySettings(
                    performance: metrics,
                    environment: environment
                )
            }
        }
    }
    
    private func getEnvironmentMetrics() async -> EnvironmentMetrics {
        // Implementation for getting environment metrics
        return EnvironmentMetrics()
    }
    
    private func adjustResolution(decrease: Bool) async {
        // Implementation for resolution adjustment
    }
    
    private func adjustMeshDetail(decrease: Bool) async {
        // Implementation for mesh detail adjustment
    }
    
    private func adjustTextureQuality(decrease: Bool) async {
        // Implementation for texture quality adjustment
    }
    
    private func adjustLightSensitivity(increase: Bool) async {
        // Implementation for light sensitivity adjustment
    }
}

// MARK: - Types

extension AdaptiveQualityManager {
    public enum QualityProfile: String {
        case maximum = "maximum"
        case high = "high"
        case balanced = "balanced"
        case reduced = "reduced"
        case minimum = "minimum"
        
        var scanningQuality: ScanningConfiguration.Quality {
            switch self {
            case .maximum: return .high
            case .high: return .high
            case .balanced: return .medium
            case .reduced: return .low
            case .minimum: return .minimum
            }
        }
    }
    
    enum QualityParameter {
        case reduceResolution
        case reduceMeshDetail
        case reduceTextureQuality
        case increaseLightSensitivity
    }
    
    public enum AdjustmentReason: String {
        case performance = "performance"
        case thermal = "thermal"
        case memory = "memory"
        case environment = "environment"
    }
    
    struct QualityAdjustment {
        let timestamp: Date
        let profile: QualityProfile?
        let parameters: [QualityParameter]
        let reason: AdjustmentReason
        let metrics: QualityMetrics
    }
    
    struct QualityMetrics {
        let performance: PerformanceMetrics
        let environment: EnvironmentMetrics
    }
    
    struct AdaptiveSettings {
        let maxFrameTime: TimeInterval = 0.033 // 30fps
        let maxMemoryUsage: Float = 0.8
        let minLightIntensity: Float = 500
        let maxGPUUtilization: Float = 0.9
    }
    
    struct EnvironmentMetrics {
        var lightIntensity: Float = 0
        var motionLevel: Float = 0
        var surfaceComplexity: Float = 0
        var ambientNoise: Float = 0
    }
}

extension AnalyticsService.Event {
    static let qualityProfileChanged = AnalyticsService.Event(name: "quality_profile_changed")
    static let qualityProfileTransition = AnalyticsService.Event(name: "quality_profile_transition")
}

extension Notification.Name {
    static let qualityProfileChanged = Notification.Name("qualityProfileChanged")
}