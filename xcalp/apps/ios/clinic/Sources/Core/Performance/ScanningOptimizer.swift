import ARKit
import Foundation
import Metal

class ScanningOptimizer {
    private let resourceMonitor: ResourceMonitoringSystem
    private let performanceMonitor: PerformanceMonitor
    private var currentOptimizationLevel: OptimizationLevel = .high
    private var lastOptimizationTime: Date = Date()
    private let minimumOptimizationInterval: TimeInterval = 2.0
    
    init(resourceMonitor: ResourceMonitoringSystem, performanceMonitor: PerformanceMonitor) {
        self.resourceMonitor = resourceMonitor
        self.performanceMonitor = performanceMonitor
    }
    
    func optimizeScanningParameters(for mode: ScanningModes) -> ScanningParameters {
        let systemLoad = resourceMonitor.getSystemLoad()
        let newOptimizationLevel = determineOptimizationLevel(based: systemLoad)
        
        if shouldUpdateOptimization(newLevel: newOptimizationLevel) {
            currentOptimizationLevel = newOptimizationLevel
            lastOptimizationTime = Date()
            
            // Notify about optimization change
            NotificationCenter.default.post(
                name: .scanningOptimizationChanged,
                object: nil,
                userInfo: ["level": newOptimizationLevel]
            )
        }
        
        return generateParameters(for: mode, optimizationLevel: currentOptimizationLevel)
    }
    
    private func determineOptimizationLevel(based systemLoad: SystemLoadMetrics) -> OptimizationLevel {
        if systemLoad.thermalState == .serious {
            return .minimum
        }
        
        let averageLoad = (systemLoad.cpuUsage + systemLoad.memoryUsage) / 2
        
        switch averageLoad {
        case 0.0...0.6:
            return .high
        case 0.6...0.8:
            return .medium
        case 0.8...0.9:
            return .low
        default:
            return .minimum
        }
    }
    
    private func shouldUpdateOptimization(newLevel: OptimizationLevel) -> Bool {
        guard Date().timeIntervalSince(lastOptimizationTime) >= minimumOptimizationInterval else {
            return false
        }
        
        return newLevel != currentOptimizationLevel
    }
    
    private func generateParameters(for mode: ScanningModes, optimizationLevel: OptimizationLevel) -> ScanningParameters {
        var parameters = ScanningParameters()
        
        switch mode {
        case .lidarOnly:
            parameters = optimizeLidarParameters(level: optimizationLevel)
        case .photogrammetryOnly:
            parameters = optimizePhotogrammetryParameters(level: optimizationLevel)
        case .hybridFusion:
            parameters = optimizeFusionParameters(level: optimizationLevel)
        }
        
        return parameters
    }
    
    private func optimizeLidarParameters(level: OptimizationLevel) -> ScanningParameters {
        var params = ScanningParameters()
        
        switch level {
        case .high:
            params.pointCloudDensity = 1.0
            params.frameProcessingInterval = 1
            params.confidenceThreshold = 0.7
            params.maxPoints = 100000
            
        case .medium:
            params.pointCloudDensity = 0.75
            params.frameProcessingInterval = 2
            params.confidenceThreshold = 0.8
            params.maxPoints = 75000
            
        case .low:
            params.pointCloudDensity = 0.5
            params.frameProcessingInterval = 3
            params.confidenceThreshold = 0.85
            params.maxPoints = 50000
            
        case .minimum:
            params.pointCloudDensity = 0.25
            params.frameProcessingInterval = 4
            params.confidenceThreshold = 0.9
            params.maxPoints = 25000
        }
        
        return params
    }
    
    private func optimizePhotogrammetryParameters(level: OptimizationLevel) -> ScanningParameters {
        var params = ScanningParameters()
        
        switch level {
        case .high:
            params.imageResolutionScale = 1.0
            params.featureExtractionQuality = .high
            params.maxFeaturePoints = 2000
            params.frameProcessingInterval = 1
            
        case .medium:
            params.imageResolutionScale = 0.75
            params.featureExtractionQuality = .balanced
            params.maxFeaturePoints = 1500
            params.frameProcessingInterval = 2
            
        case .low:
            params.imageResolutionScale = 0.5
            params.featureExtractionQuality = .balanced
            params.maxFeaturePoints = 1000
            params.frameProcessingInterval = 3
            
        case .minimum:
            params.imageResolutionScale = 0.25
            params.featureExtractionQuality = .fast
            params.maxFeaturePoints = 500
            params.frameProcessingInterval = 4
        }
        
        return params
    }
    
    private func optimizeFusionParameters(level: OptimizationLevel) -> ScanningParameters {
        var params = ScanningParameters()
        
        switch level {
        case .high:
            params.fusionQuality = .high
            params.alignmentPrecision = 0.001
            params.maxFusionPoints = 150000
            params.frameProcessingInterval = 1
            
        case .medium:
            params.fusionQuality = .balanced
            params.alignmentPrecision = 0.002
            params.maxFusionPoints = 100000
            params.frameProcessingInterval = 2
            
        case .low:
            params.fusionQuality = .fast
            params.alignmentPrecision = 0.005
            params.maxFusionPoints = 75000
            params.frameProcessingInterval = 3
            
        case .minimum:
            params.fusionQuality = .minimum
            params.alignmentPrecision = 0.01
            params.maxFusionPoints = 50000
            params.frameProcessingInterval = 4
        }
        
        return params
    }
}

enum OptimizationLevel {
    case high
    case medium
    case low
    case minimum
}

struct ScanningParameters {
    // General parameters
    var frameProcessingInterval: Int = 1
    var maxPoints: Int = 100000
    
    // LiDAR specific
    var pointCloudDensity: Float = 1.0
    var confidenceThreshold: Float = 0.7
    
    // Photogrammetry specific
    var imageResolutionScale: Float = 1.0
    var featureExtractionQuality: FeatureExtractionQuality = .high
    var maxFeaturePoints: Int = 2000
    
    // Fusion specific
    var fusionQuality: FusionQuality = .high
    var alignmentPrecision: Float = 0.001
    var maxFusionPoints: Int = 150000
}

enum FeatureExtractionQuality {
    case high
    case balanced
    case fast
}

enum FusionQuality {
    case high
    case balanced
    case fast
    case minimum
}

extension Notification.Name {
    static let scanningOptimizationChanged = Notification.Name("scanningOptimizationChanged")
}
