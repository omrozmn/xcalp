import Foundation
import ARKit
import Combine

public actor ARConfiguration {
    public static let shared = ARConfiguration()
    
    private let performanceMonitor: PerformanceMonitor
    private let analytics: AnalyticsService
    private let thermalManager: ThermalManager
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ARConfiguration")
    
    private var currentConfiguration: ARWorldTrackingConfiguration
    private var configurationPublisher = PassthroughSubject<ARWorldTrackingConfiguration, Never>()
    private var sessionQuality: SessionQuality = .high
    private var frameRateOverride: Int?
    
    private init(
        performanceMonitor: PerformanceMonitor = .shared,
        analytics: AnalyticsService = .shared,
        thermalManager: ThermalManager = .shared
    ) {
        self.performanceMonitor = performanceMonitor
        self.analytics = analytics
        self.thermalManager = thermalManager
        
        // Initialize with default configuration
        self.currentConfiguration = ARWorldTrackingConfiguration()
        setupInitialConfiguration()
    }
    
    public func setPreferredFrameRate(_ fps: Int) async {
        guard fps != frameRateOverride else { return }
        
        frameRateOverride = fps
        await updateConfiguration { config in
            config.frameSemantics = []
            config.videoFormat = selectVideoFormat(for: fps)
        }
        
        analytics.track(
            event: .arFrameRateChanged,
            properties: ["frameRate": fps]
        )
    }
    
    public func configureForQuality(_ quality: SessionQuality) async {
        guard quality != sessionQuality else { return }
        
        sessionQuality = quality
        await updateConfiguration { config in
            switch quality {
            case .high:
                configureHighQuality(&config)
            case .medium:
                configureMediumQuality(&config)
            case .low:
                configureLowQuality(&config)
            case .minimum:
                configureMinimumQuality(&config)
            }
        }
        
        analytics.track(
            event: .arQualityChanged,
            properties: ["quality": quality.rawValue]
        )
    }
    
    public func publisher() -> AnyPublisher<ARWorldTrackingConfiguration, Never> {
        configurationPublisher.eraseToAnyPublisher()
    }
    
    public func getCurrentConfiguration() -> ARWorldTrackingConfiguration {
        currentConfiguration
    }
    
    private func setupInitialConfiguration() {
        currentConfiguration.isAutoFocusEnabled = true
        currentConfiguration.environmentTexturing = .automatic
        currentConfiguration.frameSemantics = [.smoothedSceneDepth]
        currentConfiguration.sceneReconstruction = .meshWithClassification
        
        if #available(iOS 16.0, *) {
            currentConfiguration.meshingRateEnabled = true
        }
        
        // Start monitoring thermal state
        Task {
            for await thermalState in await thermalStateUpdates() {
                await handleThermalStateChange(thermalState)
            }
        }
    }
    
    private func updateConfiguration(
        _ updates: (inout ARWorldTrackingConfiguration) -> Void
    ) async {
        var newConfig = currentConfiguration
        updates(&newConfig)
        
        currentConfiguration = newConfig
        configurationPublisher.send(newConfig)
        
        await logConfigurationChange()
    }
    
    private func selectVideoFormat(for fps: Int) -> ARVideoFormat {
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        
        // Find format closest to desired frame rate
        return availableFormats.min { format1, format2 in
            abs(format1.frameRateRange.maxFrameRate - Double(fps)) <
            abs(format2.frameRateRange.maxFrameRate - Double(fps))
        } ?? availableFormats[0]
    }
    
    private func configureHighQuality(_ config: inout ARWorldTrackingConfiguration) {
        config.frameSemantics = [.smoothedSceneDepth, .sceneDepth]
        config.environmentTexturing = .automatic
        config.sceneReconstruction = .meshWithClassification
        
        if #available(iOS 16.0, *) {
            config.meshingRateEnabled = true
        }
        
        config.isAutoFocusEnabled = true
        config.videoFormat = selectVideoFormat(for: 60)
    }
    
    private func configureMediumQuality(_ config: inout ARWorldTrackingConfiguration) {
        config.frameSemantics = [.smoothedSceneDepth]
        config.environmentTexturing = .automatic
        config.sceneReconstruction = .mesh
        
        if #available(iOS 16.0, *) {
            config.meshingRateEnabled = true
        }
        
        config.isAutoFocusEnabled = true
        config.videoFormat = selectVideoFormat(for: 30)
    }
    
    private func configureLowQuality(_ config: inout ARWorldTrackingConfiguration) {
        config.frameSemantics = []
        config.environmentTexturing = .manual
        config.sceneReconstruction = .mesh
        
        if #available(iOS 16.0, *) {
            config.meshingRateEnabled = false
        }
        
        config.isAutoFocusEnabled = false
        config.videoFormat = selectVideoFormat(for: 24)
    }
    
    private func configureMinimumQuality(_ config: inout ARWorldTrackingConfiguration) {
        config.frameSemantics = []
        config.environmentTexturing = .none
        config.sceneReconstruction = .mesh
        
        if #available(iOS 16.0, *) {
            config.meshingRateEnabled = false
        }
        
        config.isAutoFocusEnabled = false
        config.videoFormat = selectVideoFormat(for: 15)
    }
    
    private func handleThermalStateChange(_ state: ThermalManager.ThermalState) async {
        switch state {
        case .nominal:
            await configureForQuality(.high)
        case .elevated:
            await configureForQuality(.medium)
        case .critical:
            await configureForQuality(.low)
        case .emergency:
            await configureForQuality(.minimum)
        }
    }
    
    private func thermalStateUpdates() async -> AsyncStream<ThermalManager.ThermalState> {
        AsyncStream { continuation in
            Task {
                while !Task.isCancelled {
                    continuation.yield(await thermalManager.getCurrentThermalState())
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
            }
        }
    }
    
    private func logConfigurationChange() async {
        let configDescription = """
        Frame Rate: \(currentConfiguration.videoFormat.frameRateRange.maxFrameRate)
        Quality: \(sessionQuality.rawValue)
        Scene Reconstruction: \(currentConfiguration.sceneReconstruction.rawValue)
        Environment Texturing: \(currentConfiguration.environmentTexturing.rawValue)
        """
        
        logger.info("AR configuration updated: \(configDescription)")
    }
}

// MARK: - Types

extension ARConfiguration {
    public enum SessionQuality: String {
        case high
        case medium
        case low
        case minimum
    }
}

extension AnalyticsService.Event {
    static let arFrameRateChanged = AnalyticsService.Event(name: "ar_frame_rate_changed")
    static let arQualityChanged = AnalyticsService.Event(name: "ar_quality_changed")
}