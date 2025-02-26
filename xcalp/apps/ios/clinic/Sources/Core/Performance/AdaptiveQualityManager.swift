import Foundation
import MetalKit
import Combine

public class AdaptiveQualityManager {
    public static let shared = AdaptiveQualityManager()
    
    private var currentSettings: QualitySettings
    private var performanceHistory: [ResourceMetrics] = []
    private let historyLimit = 10
    private let updateThreshold: TimeInterval = 2.0
    private var lastUpdate: Date = .distantPast
    
    private init() {
        self.currentSettings = QualitySettings()
    }
    
    public func updateQualitySettings(
        performance: ResourceMetrics,
        environment: EnvironmentMetrics
    ) async {
        guard Date().timeIntervalSince(lastUpdate) >= updateThreshold else { return }
        
        // Update performance history
        performanceHistory.append(performance)
        if performanceHistory.count > historyLimit {
            performanceHistory.removeFirst()
        }
        
        // Calculate new settings based on performance and environment
        let newSettings = calculateOptimalSettings(
            performance: performance,
            environment: environment
        )
        
        // Apply changes gradually if needed
        await applySettingsChanges(newSettings)
        
        lastUpdate = Date()
    }
    
    private func calculateOptimalSettings(
        performance: ResourceMetrics,
        environment: EnvironmentMetrics
    ) -> QualitySettings {
        var settings = QualitySettings()
        
        // Adjust mesh density based on GPU performance
        settings.meshDensity = calculateMeshDensity(
            gpuUtilization: performance.gpuUtilization,
            frameRate: performance.frameRate
        )
        
        // Adjust processing quality based on CPU usage
        settings.processingQuality = calculateProcessingQuality(
            cpuUsage: performance.cpuUsage
        )
        
        // Adjust scan resolution based on available memory
        settings.scanResolution = calculateScanResolution(
            memoryUsage: performance.memoryUsage
        )
        
        // Factor in environmental conditions
        settings.lightingCompensation = calculateLightingCompensation(
            lightingLevel: environment.lightingLevel
        )
        
        // Adjust for motion stability
        settings.motionTolerance = calculateMotionTolerance(
            motionStability: environment.motionStability
        )
        
        // Consider thermal state
        if performance.thermalState == .serious {
            settings.applyThermalRestrictions()
        }
        
        return settings
    }
    
    private func calculateMeshDensity(
        gpuUtilization: Double,
        frameRate: Double
    ) -> Float {
        let baseValue: Float = 1.0
        let utilizationFactor = Float(1.0 - gpuUtilization)
        let frameRateFactor = Float(min(frameRate / 30.0, 1.0))
        
        return baseValue * utilizationFactor * frameRateFactor
    }
    
    private func calculateProcessingQuality(cpuUsage: Double) -> Float {
        let baseQuality: Float = 1.0
        let usageFactor = Float(1.0 - cpuUsage)
        
        return baseQuality * usageFactor
    }
    
    private func calculateScanResolution(memoryUsage: UInt64) -> Float {
        let maxMemory = AppConfiguration.Performance.Thresholds.maxMemoryUsage
        let memoryFactor = Float(1.0 - Double(memoryUsage) / Double(maxMemory))
        
        return max(0.5, memoryFactor) // Minimum 50% resolution
    }
    
    private func calculateLightingCompensation(lightingLevel: Double) -> Float {
        return Float(1.0 / max(lightingLevel, 0.5)) // Increase compensation in low light
    }
    
    private func calculateMotionTolerance(motionStability: Double) -> Float {
        return Float(max(0.5, motionStability)) // More tolerant when unstable
    }
    
    private func applySettingsChanges(_ newSettings: QualitySettings) async {
        // Gradually interpolate between current and new settings
        let alpha: Float = 0.3 // Smoothing factor
        
        currentSettings.meshDensity = lerp(
            currentSettings.meshDensity,
            newSettings.meshDensity,
            alpha
        )
        
        currentSettings.processingQuality = lerp(
            currentSettings.processingQuality,
            newSettings.processingQuality,
            alpha
        )
        
        currentSettings.scanResolution = lerp(
            currentSettings.scanResolution,
            newSettings.scanResolution,
            alpha
        )
        
        currentSettings.lightingCompensation = lerp(
            currentSettings.lightingCompensation,
            newSettings.lightingCompensation,
            alpha
        )
        
        currentSettings.motionTolerance = lerp(
            currentSettings.motionTolerance,
            newSettings.motionTolerance,
            alpha
        )
        
        NotificationCenter.default.post(
            name: .qualitySettingsDidChange,
            object: self,
            userInfo: ["settings": currentSettings]
        )
    }
    
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }
}

public struct QualitySettings: Codable {
    public var meshDensity: Float = 1.0
    public var processingQuality: Float = 1.0
    public var scanResolution: Float = 1.0
    public var lightingCompensation: Float = 1.0
    public var motionTolerance: Float = 1.0
    
    mutating func applyThermalRestrictions() {
        meshDensity *= 0.7
        processingQuality *= 0.6
        scanResolution *= 0.8
    }
}

extension Notification.Name {
    public static let qualitySettingsDidChange = Notification.Name("qualitySettingsDidChange")
}