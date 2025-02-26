import Foundation
import MetalKit

class ScalabilityManager {
    static let shared = ScalabilityManager()
    
    private let resourceMonitor = ResourceMonitor()
    private let performanceProfiler = PerformanceProfiler()
    
    // Resource limits and thresholds
    struct ResourceLimits {
        static let maxMemoryUsage: UInt64 = 750_000_000  // 750MB
        static let maxCPUUsage: Float = 0.8              // 80%
        static let maxGPUUsage: Float = 0.75             // 75%
        static let maxConcurrentOperations = 3
        static let maxBatchSize = 1000
    }
    
    private var currentLoadLevel: LoadLevel = .normal {
        didSet {
            if oldValue != currentLoadLevel {
                handleLoadLevelChange(from: oldValue, to: currentLoadLevel)
            }
        }
    }
    
    func monitorResources() {
        Task {
            for await metrics in resourceMonitor.metrics {
                updateLoadLevel(based: metrics)
                applyResourceLimits(metrics)
            }
        }
    }
    
    func checkOperationViability(_ operation: ProcessingOperation) -> OperationViability {
        let currentMetrics = resourceMonitor.currentMetrics
        
        // Check if we have enough resources
        guard currentMetrics.memoryUsage < ResourceLimits.maxMemoryUsage,
              currentMetrics.cpuUsage < ResourceLimits.maxCPUUsage else {
            return .notViable(reason: "Insufficient resources")
        }
        
        // Check operation specific requirements
        let requirements = calculateResourceRequirements(for: operation)
        guard canAccommodate(requirements) else {
            return .needsOptimization(
                suggestion: suggestOptimization(for: operation, metrics: currentMetrics)
            )
        }
        
        return .viable(
            estimatedDuration: estimateProcessingTime(for: operation),
            suggestedBatchSize: calculateOptimalBatchSize(for: operation)
        )
    }
    
    func optimizeForCurrentLoad() {
        switch currentLoadLevel {
        case .normal:
            MetalConfiguration.shared.setQualityLevel(.high)
            ProcessingConfiguration.shared.setBatchSize(ResourceLimits.maxBatchSize)
            
        case .elevated:
            MetalConfiguration.shared.setQualityLevel(.medium)
            ProcessingConfiguration.shared.setBatchSize(ResourceLimits.maxBatchSize / 2)
            
        case .critical:
            MetalConfiguration.shared.setQualityLevel(.low)
            ProcessingConfiguration.shared.setBatchSize(ResourceLimits.maxBatchSize / 4)
            performanceProfiler.cancelNonEssentialOperations()
        }
    }
}

private extension ScalabilityManager {
    enum LoadLevel {
        case normal
        case elevated
        case critical
    }
    
    func updateLoadLevel(based metrics: ResourceMetrics) {
        let newLevel: LoadLevel
        
        switch (metrics.cpuUsage, metrics.memoryUsage) {
        case let (cpu, _) where cpu > 0.9:
            newLevel = .critical
        case let (cpu, memory) where cpu > 0.7 || memory > ResourceLimits.maxMemoryUsage * 0.8:
            newLevel = .elevated
        default:
            newLevel = .normal
        }
        
        currentLoadLevel = newLevel
    }
    
    func handleLoadLevelChange(from oldLevel: LoadLevel, to newLevel: LoadLevel) {
        logger.info("Load level changed from \(oldLevel) to \(newLevel)")
        optimizeForCurrentLoad()
        
        NotificationCenter.default.post(
            name: .loadLevelChanged,
            object: nil,
            userInfo: ["level": newLevel]
        )
    }
    
    func applyResourceLimits(_ metrics: ResourceMetrics) {
        if metrics.memoryUsage > ResourceLimits.maxMemoryUsage {
            performanceProfiler.reduceMemoryUsage()
        }
        
        if metrics.cpuUsage > ResourceLimits.maxCPUUsage {
            performanceProfiler.reduceCPULoad()
        }
        
        if metrics.gpuUsage > ResourceLimits.maxGPUUsage {
            MetalConfiguration.shared.reduceQuality()
        }
    }
}

enum OperationViability {
    case viable(estimatedDuration: TimeInterval, suggestedBatchSize: Int)
    case needsOptimization(suggestion: OptimizationSuggestion)
    case notViable(reason: String)
}

struct OptimizationSuggestion {
    let action: OptimizationAction
    let expectedImprovement: Float
    let resourceImpact: ResourceImpact
}

enum OptimizationAction {
    case reduceBatchSize(to: Int)
    case lowerQuality(to: QualityLevel)
    case deferOperation(until: Date)
    case splitOperation
}