import Foundation
import os.log
import CoreData

public class PerformanceAnalytics {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "PerformanceAnalytics")
    private let dataStore: ScanningDataStore
    private let metricsQueue: DispatchQueue
    private var currentSessionMetrics: [SessionMetric] = []
    
    private var sessionStartTime: Date?
    private var lastMetricTime: Date?
    private let minimumMetricInterval: TimeInterval = 0.1
    
    public init(dataStore: ScanningDataStore = .shared) {
        self.dataStore = dataStore
        self.metricsQueue = DispatchQueue(
            label: "com.xcalp.analytics",
            qos: .utility
        )
    }
    
    public func startSession(sessionID: UUID) {
        sessionStartTime = Date()
        currentSessionMetrics.removeAll()
        
        logger.info("Started performance tracking for session: \(sessionID.uuidString)")
    }
    
    public func recordMetric(
        type: MetricType,
        value: Double,
        context: [String: Any] = [:]
    ) {
        guard let startTime = sessionStartTime else { return }
        
        // Ensure minimum interval between metrics
        if let lastTime = lastMetricTime,
           Date().timeIntervalSince(lastTime) < minimumMetricInterval {
            return
        }
        
        let metric = SessionMetric(
            timestamp: Date(),
            timeOffset: Date().timeIntervalSince(startTime),
            type: type,
            value: value,
            context: context
        )
        
        metricsQueue.async { [weak self] in
            self?.currentSessionMetrics.append(metric)
            self?.lastMetricTime = Date()
        }
    }
    
    public func endSession(sessionID: UUID) async throws {
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        let analysis = await analyzeSessionMetrics()
        
        // Store session analytics
        try await storeSessionAnalytics(
            sessionID: sessionID,
            duration: sessionDuration,
            analysis: analysis
        )
        
        // Log summary
        logSessionSummary(analysis)
        
        // Reset session state
        sessionStartTime = nil
        currentSessionMetrics.removeAll()
        
        logger.info("Ended performance tracking for session: \(sessionID.uuidString)")
    }
    
    public func getPerformanceReport(
        sessionID: UUID
    ) async throws -> PerformanceReport {
        // Retrieve session data
        let metrics = try await dataStore.getSessionMetrics(sessionID)
        let analysis = try await dataStore.getSessionAnalysis(sessionID)
        
        return PerformanceReport(
            sessionID: sessionID,
            metrics: metrics,
            analysis: analysis
        )
    }
    
    public func getAggregateStats(
        timeRange: TimeRange = .lastWeek
    ) async throws -> AggregateStats {
        let sessions = try await dataStore.getSessionsInRange(timeRange)
        
        var totalDuration: TimeInterval = 0
        var totalScans = 0
        var successfulScans = 0
        var averageQuality: Double = 0
        var averagePerformance: ResourceMetrics?
        
        for session in sessions {
            if let analysis = try await dataStore.getSessionAnalysis(session.id!) {
                totalDuration += analysis.duration
                totalScans += 1
                
                if analysis.success {
                    successfulScans += 1
                }
                
                averageQuality += analysis.averageQuality
                
                if let performance = analysis.averagePerformance {
                    averagePerformance = averagePerformance?.combine(with: performance) ?? performance
                }
            }
        }
        
        if totalScans > 0 {
            averageQuality /= Double(totalScans)
            if let performance = averagePerformance {
                averagePerformance = performance.averaged(by: totalScans)
            }
        }
        
        return AggregateStats(
            timeRange: timeRange,
            totalScans: totalScans,
            successRate: Double(successfulScans) / Double(totalScans),
            averageDuration: totalDuration / Double(totalScans),
            averageQuality: averageQuality,
            averagePerformance: averagePerformance
        )
    }
    
    // MARK: - Private Methods
    
    private func analyzeSessionMetrics() async -> SessionAnalysis {
        var analysis = SessionAnalysis()
        
        // Group metrics by type
        let groupedMetrics = Dictionary(grouping: currentSessionMetrics) { $0.type }
        
        // Analyze quality metrics
        if let qualityMetrics = groupedMetrics[.quality] {
            analysis.averageQuality = qualityMetrics.average { $0.value }
            analysis.minQuality = qualityMetrics.min { $0.value < $1.value }?.value ?? 0
            analysis.maxQuality = qualityMetrics.max { $0.value < $1.value }?.value ?? 0
        }
        
        // Analyze performance metrics
        if let performanceMetrics = groupedMetrics[.performance] {
            let avgCPU = performanceMetrics.average { metric in
                (metric.context["cpuUsage"] as? Double) ?? 0
            }
            let avgMemory = performanceMetrics.average { metric in
                Double((metric.context["memoryUsage"] as? UInt64) ?? 0)
            }
            let avgGPU = performanceMetrics.average { metric in
                (metric.context["gpuUtilization"] as? Double) ?? 0
            }
            
            analysis.averagePerformance = ResourceMetrics(
                cpuUsage: avgCPU,
                memoryUsage: UInt64(avgMemory),
                gpuUtilization: avgGPU
            )
        }
        
        // Analyze frame rate
        if let fpsMetrics = groupedMetrics[.frameRate] {
            analysis.averageFrameRate = fpsMetrics.average { $0.value }
            analysis.minFrameRate = fpsMetrics.min { $0.value < $1.value }?.value ?? 0
            analysis.maxFrameRate = fpsMetrics.max { $0.value < $1.value }?.value ?? 0
        }
        
        // Determine session success
        analysis.success = analysis.averageQuality >= AppConfiguration.Performance.Scanning.minFeaturePreservation
        
        return analysis
    }
    
    private func storeSessionAnalytics(
        sessionID: UUID,
        duration: TimeInterval,
        analysis: SessionAnalysis
    ) async throws {
        // Store metrics
        try await dataStore.storeMetrics(
            currentSessionMetrics,
            for: sessionID
        )
        
        // Store analysis
        var analysisDict: [String: Any] = [
            "duration": duration,
            "success": analysis.success,
            "averageQuality": analysis.averageQuality,
            "minQuality": analysis.minQuality,
            "maxQuality": analysis.maxQuality,
            "averageFrameRate": analysis.averageFrameRate,
            "minFrameRate": analysis.minFrameRate,
            "maxFrameRate": analysis.maxFrameRate
        ]
        
        if let performance = analysis.averagePerformance {
            analysisDict["averagePerformance"] = performance
        }
        
        try await dataStore.storeAnalysis(
            analysisDict,
            for: sessionID
        )
    }
    
    private func logSessionSummary(_ analysis: SessionAnalysis) {
        let summary = """
        Session Summary:
        Success: \(analysis.success)
        Average Quality: \(String(format: "%.2f", analysis.averageQuality))
        Frame Rate: \(String(format: "%.1f", analysis.averageFrameRate)) fps
        CPU Usage: \(String(format: "%.1f%%", analysis.averagePerformance?.cpuUsage ?? 0 * 100))
        Memory Usage: \(ByteCountFormatter.string(fromByteCount: Int64(analysis.averagePerformance?.memoryUsage ?? 0), countStyle: .memory))
        GPU Utilization: \(String(format: "%.1f%%", analysis.averagePerformance?.gpuUtilization ?? 0 * 100))
        """
        
        logger.info("\(summary)")
    }
}

// MARK: - Supporting Types

public enum MetricType: String {
    case quality
    case performance
    case frameRate
    case memory
    case thermal
}

public struct SessionMetric {
    let timestamp: Date
    let timeOffset: TimeInterval
    let type: MetricType
    let value: Double
    let context: [String: Any]
}

public struct SessionAnalysis {
    var success: Bool = false
    var averageQuality: Double = 0
    var minQuality: Double = 0
    var maxQuality: Double = 0
    var averageFrameRate: Double = 0
    var minFrameRate: Double = 0
    var maxFrameRate: Double = 0
    var averagePerformance: ResourceMetrics?
    var duration: TimeInterval = 0
    
    var meetsPerformanceTargets: Bool {
        guard let performance = averagePerformance else { return false }
        
        return averageFrameRate >= PerformanceThresholds.minimumFrameRate &&
               performance.cpuUsage <= PerformanceThresholds.maximumCPUUsage &&
               performance.gpuUtilization <= PerformanceThresholds.maximumGPUUsage &&
               averageQuality >= PerformanceThresholds.ScanQuality.minimumFeatureConfidence
    }
    
    func generatePerformanceReport() -> String {
        var summary = """
        Session Summary:
        Success: \(success)
        Average Quality: \(String(format: "%.2f", averageQuality))
        Frame Rate: \(String(format: "%.1f", averageFrameRate)) fps
        CPU Usage: \(String(format: "%.1f%%", averagePerformance?.cpuUsage ?? 0 * 100))
        Memory Usage: \(ByteCountFormatter.string(fromByteCount: Int64(averagePerformance?.memoryUsage ?? 0), countStyle: .memory))
        GPU Utilization: \(String(format: "%.1f%%", averagePerformance?.gpuUtilization ?? 0 * 100))
        """
        
        summary.append("Performance Metrics:\n")
        summary.append("- Frame Rate: \(String(format: "%.1f", averageFrameRate)) fps (Target: \(PerformanceThresholds.targetFrameRate))\n")
        summary.append("- Quality Score: \(String(format: "%.2f", averageQuality)) (Min: \(PerformanceThresholds.ScanQuality.minimumFeatureConfidence))\n")
        
        if let performance = averagePerformance {
            summary.append("- CPU Usage: \(String(format: "%.1f%%", performance.cpuUsage * 100))\n")
            summary.append("- GPU Usage: \(String(format: "%.1f%%", performance.gpuUtilization * 100))\n")
        }
        
        return summary
    }
}

public struct PerformanceReport {
    public let sessionID: UUID
    public let metrics: [SessionMetric]
    public let analysis: SessionAnalysis
}

public enum TimeRange {
    case lastDay
    case lastWeek
    case lastMonth
    case custom(from: Date, to: Date)
    
    var interval: TimeInterval {
        switch self {
        case .lastDay: return 86400
        case .lastWeek: return 604800
        case .lastMonth: return 2592000
        case .custom(let from, let to): return to.timeIntervalSince(from)
        }
    }
}

public struct AggregateStats {
    public let timeRange: TimeRange
    public let totalScans: Int
    public let successRate: Double
    public let averageDuration: TimeInterval
    public let averageQuality: Double
    public let averagePerformance: ResourceMetrics?
}

// MARK: - Extensions

extension Array where Element == SessionMetric {
    func average(_ getValue: (Element) -> Double) -> Double {
        guard !isEmpty else { return 0 }
        let sum = reduce(0.0) { $0 + getValue($1) }
        return sum / Double(count)
    }
}

extension ResourceMetrics {
    func combine(with other: ResourceMetrics) -> ResourceMetrics {
        ResourceMetrics(
            cpuUsage: cpuUsage + other.cpuUsage,
            memoryUsage: memoryUsage + other.memoryUsage,
            gpuUtilization: gpuUtilization + other.gpuUtilization
        )
    }
    
    func averaged(by count: Int) -> ResourceMetrics {
        ResourceMetrics(
            cpuUsage: cpuUsage / Double(count),
            memoryUsage: memoryUsage / UInt64(count),
            gpuUtilization: gpuUtilization / Double(count)
        )
    }
}

struct PerformanceThresholds {
    static let minimumFrameRate: Double = 30.0
    static let targetFrameRate: Double = 60.0
    static let maximumProcessingTime: TimeInterval = 3.0
    static let maximumMemoryUsage: UInt64 = 300_000_000 // 300MB
    static let maximumCPUUsage: Float = 0.8 // 80%
    static let maximumGPUUsage: Float = 0.7 // 70%
    
    struct ScanQuality {
        static let minimumPointDensity: Float = 1000 // points per cm²
        static let minimumFeatureConfidence: Float = 0.85
        static let maximumNoiseLevel: Float = 0.15
        static let minimumSurfaceCompleteness: Float = 0.95
    }
    
    struct Analysis {
        static let maximumAnalysisTime: TimeInterval = 5.0
        static let minimumConfidenceScore: Double = 0.9
        static let maximumMLInferenceTime: TimeInterval = 2.0
    }
}