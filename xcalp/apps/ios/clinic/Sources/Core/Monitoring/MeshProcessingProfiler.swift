import Foundation
import Metal
import MetalPerformanceShaders
import os.log

final class MeshProcessingProfiler {
    static let shared = MeshProcessingProfiler()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let device: MTLDevice
    private let queue = DispatchQueue(label: "com.xcalp.profiler", qos: .utility)
    
    private var metrics: [String: [PerformanceMetric]] = [:]
    private var stageDurations: [ProcessingStage: [TimeInterval]] = [:]
    private var memoryUsage: RingBuffer<MemoryMetric>
    private var gpuCounters: MTLCounterSet?
    
    private let updateInterval: TimeInterval = 1.0
    private let metricsRetention: TimeInterval = 300.0  // 5 minutes
    private var lastCleanup = Date()
    
    struct PerformanceMetric {
        let timestamp: Date
        let value: Double
        let metadata: [String: Any]
    }
    
    struct MemoryMetric {
        let timestamp: Date
        let used: UInt64
        let peak: UInt64
        let allocations: Int
    }
    
    enum ProcessingStage: String {
        case featureDetection = "Feature Detection"
        case meshDecimation = "Mesh Decimation"
        case qualityAnalysis = "Quality Analysis"
        case optimization = "Optimization"
        case featurePreservation = "Feature Preservation"
    }
    
    struct StageProfile {
        let stage: ProcessingStage
        let duration: TimeInterval
        let memoryDelta: Int64
        let gpuUtilization: Double
    }
    
    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.memoryUsage = RingBuffer(capacity: 3600)  // 1 hour at 1 sample/second
        
        setupMetalProfiling()
        startPeriodicUpdates()
    }
    
    // MARK: - Public Methods
    
    func beginStage(_ stage: ProcessingStage) -> OSSignpostID {
        let signpostID = signposter.makeSignpostID()
        signposter.emitBeginEvent(for: stage, id: signpostID)
        
        let initialMemory = getMemoryUsage()
        queue.async {
            self.trackStageStart(stage, memory: initialMemory)
        }
        
        return signpostID
    }
    
    func endStage(_ stage: ProcessingStage, signpostID: OSSignpostID) {
        signposter.emitEndEvent(for: stage, id: signpostID)
        
        let finalMemory = getMemoryUsage()
        queue.async {
            self.trackStageEnd(stage, memory: finalMemory)
        }
    }
    
    func recordMetric(
        _ name: String,
        value: Double,
        metadata: [String: Any] = [:]
    ) {
        queue.async {
            let metric = PerformanceMetric(
                timestamp: Date(),
                value: value,
                metadata: metadata
            )
            
            self.metrics[name, default: []].append(metric)
            self.cleanupOldMetrics()
        }
    }
    
    func getStageStatistics(
        _ stage: ProcessingStage,
        window: TimeInterval = 60
    ) -> StageStatistics {
        queue.sync {
            let now = Date()
            let recentDurations = stageDurations[stage, default: []]
                .filter { $0 <= window }
            
            return StageStatistics(
                averageDuration: recentDurations.average,
                minimumDuration: recentDurations.min() ?? 0,
                maximumDuration: recentDurations.max() ?? 0,
                standardDeviation: recentDurations.standardDeviation
            )
        }
    }
    
    func generatePerformanceReport() -> PerformanceReport {
        queue.sync {
            let memoryStats = calculateMemoryStatistics()
            let stageStats = generateStageStatistics()
            let gpuStats = getGPUStatistics()
            
            return PerformanceReport(
                timestamp: Date(),
                stages: stageStats,
                memoryUsage: memoryStats,
                gpuUtilization: gpuStats,
                recommendations: generateOptimizationRecommendations(
                    memoryStats: memoryStats,
                    stageStats: stageStats,
                    gpuStats: gpuStats
                )
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMetalProfiling() {
        if #available(iOS 14.0, *) {
            gpuCounters = device.counterSets.first { $0.name == "Statistics" }
        }
    }
    
    private func startPeriodicUpdates() {
        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.queue.async {
                self?.updateMetrics()
            }
        }
    }
    
    private func trackStageStart(
        _ stage: ProcessingStage,
        memory: UInt64
    ) {
        recordMetric(
            "stage_start_\(stage.rawValue)",
            value: Double(memory),
            metadata: ["stage": stage.rawValue]
        )
    }
    
    private func trackStageEnd(
        _ stage: ProcessingStage,
        memory: UInt64
    ) {
        recordMetric(
            "stage_end_\(stage.rawValue)",
            value: Double(memory),
            metadata: ["stage": stage.rawValue]
        )
    }
    
    private func updateMetrics() {
        // Update memory metrics
        let currentMemory = getMemoryUsage()
        let peakMemory = getPeakMemoryUsage()
        let allocations = getAllocationCount()
        
        memoryUsage.append(MemoryMetric(
            timestamp: Date(),
            used: currentMemory,
            peak: peakMemory,
            allocations: allocations
        ))
        
        // Clean up old metrics if needed
        cleanupOldMetrics()
        
        // Log current state
        logger.debug("""
            Performance update:
            Memory: \(ByteCountFormatter.string(fromByteCount: Int64(currentMemory), countStyle: .memory))
            Peak: \(ByteCountFormatter.string(fromByteCount: Int64(peakMemory), countStyle: .memory))
            Allocations: \(allocations)
            """)
    }
    
    private func cleanupOldMetrics() {
        guard Date().timeIntervalSince(lastCleanup) >= 60 else { return }
        
        let cutoff = Date().addingTimeInterval(-metricsRetention)
        
        // Clean up metrics
        for (key, value) in metrics {
            metrics[key] = value.filter { $0.timestamp > cutoff }
        }
        
        // Clean up memory usage history
        memoryUsage = RingBuffer(
            elements: memoryUsage.elements.filter { $0.timestamp > cutoff },
            capacity: memoryUsage.capacity
        )
        
        lastCleanup = Date()
    }
    
    private func calculateMemoryStatistics() -> MemoryStatistics {
        let recentMetrics = memoryUsage.elements.suffix(60)  // Last minute
        
        let averageUsage = recentMetrics.map { Double($0.used) }.average
        let peakUsage = recentMetrics.map { $0.peak }.max() ?? 0
        let averageAllocations = recentMetrics.map { Double($0.allocations) }.average
        
        return MemoryStatistics(
            averageUsage: UInt64(averageUsage),
            peakUsage: peakUsage,
            averageAllocations: Int(averageAllocations)
        )
    }
    
    private func generateStageStatistics() -> [ProcessingStage: StageStatistics] {
        var stats: [ProcessingStage: StageStatistics] = [:]
        
        for stage in ProcessingStage.allCases {
            stats[stage] = getStageStatistics(stage)
        }
        
        return stats
    }
    
    private func getGPUStatistics() -> GPUStatistics {
        guard let counterSample = self.gpuCounters?.sample() else {
            return GPUStatistics(
                utilization: 0,
                memoryUsage: 0,
                bandwidth: 0
            )
        }
        
        return GPUStatistics(
            utilization: counterSample["utilization"] as? Double ?? 0,
            memoryUsage: counterSample["memoryUsed"] as? UInt64 ?? 0,
            bandwidth: counterSample["bandwidth"] as? Double ?? 0
        )
    }
    
    private func generateOptimizationRecommendations(
        memoryStats: MemoryStatistics,
        stageStats: [ProcessingStage: StageStatistics],
        gpuStats: GPUStatistics
    ) -> [OptimizationRecommendation] {
        var recommendations: [OptimizationRecommendation] = []
        
        // Check memory usage
        if memoryStats.averageUsage > 150_000_000 {  // 150MB
            recommendations.append(OptimizationRecommendation(
                type: .memoryUsage,
                priority: .high,
                description: "High memory usage detected",
                suggestedAction: "Consider batch processing or reducing mesh complexity"
            ))
        }
        
        // Check GPU utilization
        if gpuStats.utilization > 0.9 {  // 90%
            recommendations.append(OptimizationRecommendation(
                type: .gpuUtilization,
                priority: .medium,
                description: "High GPU utilization",
                suggestedAction: "Consider reducing shader complexity or batch size"
            ))
        }
        
        // Check stage durations
        for (stage, stats) in stageStats {
            if stats.averageDuration > getThresholdForStage(stage) {
                recommendations.append(OptimizationRecommendation(
                    type: .stageDuration,
                    priority: .medium,
                    description: "Long duration in \(stage.rawValue)",
                    suggestedAction: "Optimize \(stage.rawValue.lowercased()) processing"
                ))
            }
        }
        
        return recommendations.sorted { $0.priority > $1.priority }
    }
    
    private func getThresholdForStage(_ stage: ProcessingStage) -> TimeInterval {
        switch stage {
        case .featureDetection: return 0.1
        case .meshDecimation: return 0.5
        case .qualityAnalysis: return 0.1
        case .optimization: return 0.3
        case .featurePreservation: return 0.2
        }
    }
}

// MARK: - Supporting Types

extension MeshProcessingProfiler {
    struct StageStatistics {
        let averageDuration: TimeInterval
        let minimumDuration: TimeInterval
        let maximumDuration: TimeInterval
        let standardDeviation: TimeInterval
    }
    
    struct MemoryStatistics {
        let averageUsage: UInt64
        let peakUsage: UInt64
        let averageAllocations: Int
    }
    
    struct GPUStatistics {
        let utilization: Double
        let memoryUsage: UInt64
        let bandwidth: Double
    }
    
    struct OptimizationRecommendation {
        enum RecommendationType {
            case memoryUsage
            case gpuUtilization
            case stageDuration
        }
        
        enum Priority: Int, Comparable {
            case low = 0
            case medium = 1
            case high = 2
            
            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
        
        let type: RecommendationType
        let priority: Priority
        let description: String
        let suggestedAction: String
    }
    
    struct PerformanceReport {
        let timestamp: Date
        let stages: [ProcessingStage: StageStatistics]
        let memoryUsage: MemoryStatistics
        let gpuUtilization: GPUStatistics
        let recommendations: [OptimizationRecommendation]
    }
}

// MARK: - Helper Extensions

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
    
    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let avg = average
        let variance = map { pow($0 - avg, 2) }.average
        return sqrt(variance)
    }
}

private extension ProcessingStage {
    static var allCases: [ProcessingStage] {
        [.featureDetection, .meshDecimation, .qualityAnalysis, .optimization, .featurePreservation]
    }
}