import Foundation
import ARKit
import Metal
import Combine

public actor ScanSessionProfiler {
    public static let shared = ScanSessionProfiler()
    
    private let performanceMonitor: ScanPerformanceMonitor
    private let calibrationManager: ScanCalibrationManager
    private let analytics: AnalyticsService
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanProfiling")
    
    private var activeSessions: [UUID: ProfilingSession] = [:]
    private var profileCache = ProfileCache()
    
    private init(
        performanceMonitor: ScanPerformanceMonitor = .shared,
        calibrationManager: ScanCalibrationManager = .shared,
        analytics: AnalyticsService = .shared
    ) {
        self.performanceMonitor = performanceMonitor
        self.calibrationManager = calibrationManager
        self.analytics = analytics
    }
    
    public func beginProfiling(
        scanId: UUID,
        configuration: ScanConfiguration
    ) async -> ProfilingSession {
        let session = ProfilingSession(
            id: UUID(),
            scanId: scanId,
            configuration: configuration,
            startTime: Date()
        )
        
        activeSessions[session.id] = session
        
        // Start collecting metrics
        await startMetricCollection(for: session)
        
        analytics.track(
            event: .profilingStarted,
            properties: [
                "sessionId": session.id.uuidString,
                "scanId": scanId.uuidString,
                "configurationType": configuration.type.rawValue
            ]
        )
        
        return session
    }
    
    public func recordEvent(
        _ event: ProfilingEvent,
        session: ProfilingSession
    ) async {
        guard var currentSession = activeSessions[session.id] else { return }
        
        // Record event with timing
        let timestamp = Date()
        let metrics = await collectCurrentMetrics()
        
        let eventRecord = EventRecord(
            event: event,
            timestamp: timestamp,
            metrics: metrics
        )
        
        currentSession.events.append(eventRecord)
        activeSessions[session.id] = currentSession
        
        // Check for significant events
        if event.significance == .high {
            await analyzeSignificantEvent(eventRecord, in: currentSession)
        }
    }
    
    public func endProfiling(
        _ session: ProfilingSession
    ) async throws -> ProfilingReport {
        guard var currentSession = activeSessions[session.id] else {
            throw ProfilingError.sessionNotFound
        }
        
        currentSession.endTime = Date()
        
        // Generate profile report
        let report = try await generateProfilingReport(for: currentSession)
        
        // Cache session data
        profileCache.add(session: currentSession, report: report)
        
        // Generate optimization suggestions
        let suggestions = try await generateOptimizationSuggestions(
            from: report
        )
        
        // Update calibration if needed
        if report.requiresCalibration {
            await updateCalibration(based: report)
        }
        
        // Clean up
        activeSessions.removeValue(forKey: session.id)
        
        analytics.track(
            event: .profilingCompleted,
            properties: [
                "sessionId": session.id.uuidString,
                "scanId": session.scanId.uuidString,
                "duration": report.duration,
                "performanceScore": report.performanceScore,
                "suggestionCount": suggestions.count
            ]
        )
        
        return report
    }
    
    private func startMetricCollection(for session: ProfilingSession) async {
        Task {
            while activeSessions[session.id] != nil {
                let metrics = await collectCurrentMetrics()
                await processMetrics(metrics, for: session)
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func collectCurrentMetrics() async -> PerformanceMetrics {
        let systemMetrics = performanceMonitor.reportResourceMetrics()
        let thermalState = await thermalManager.getCurrentThermalState()
        
        return PerformanceMetrics(
            cpuUsage: systemMetrics.cpuUsage,
            gpuUsage: systemMetrics.gpuUsage,
            memoryUsage: systemMetrics.memoryUsage,
            thermalState: thermalState,
            frameRate: await ARConfiguration.shared.currentFrameRate,
            timestamp: Date()
        )
    }
    
    private func processMetrics(
        _ metrics: PerformanceMetrics,
        for session: ProfilingSession
    ) async {
        guard var currentSession = activeSessions[session.id] else { return }
        
        // Update running statistics
        currentSession.statistics.update(with: metrics)
        
        // Check for performance anomalies
        if let anomaly = detectAnomaly(metrics, history: currentSession.statistics) {
            await handleAnomaly(anomaly, in: currentSession)
        }
        
        activeSessions[session.id] = currentSession
    }
    
    private func analyzeSignificantEvent(
        _ event: EventRecord,
        in session: ProfilingSession
    ) async {
        // Analyze performance impact
        let impact = calculateEventImpact(event, session: session)
        
        if impact.severity >= .high {
            // Log significant impact
            logger.warning("""
                Significant performance impact detected:
                Event: \(event.event.name)
                Impact: \(impact.description)
                """
            )
            
            // Track analytics
            analytics.track(
                event: .significantPerformanceImpact,
                properties: [
                    "sessionId": session.id.uuidString,
                    "eventType": event.event.name,
                    "impactSeverity": impact.severity.rawValue,
                    "metrics": impact.metrics
                ]
            )
        }
    }
    
    private func generateProfilingReport(
        for session: ProfilingSession
    ) async throws -> ProfilingReport {
        // Calculate performance metrics
        let performanceScore = calculatePerformanceScore(session)
        
        // Analyze bottlenecks
        let bottlenecks = identifyBottlenecks(session)
        
        // Generate optimization paths
        let optimizationPaths = generateOptimizationPaths(
            bottlenecks: bottlenecks,
            session: session
        )
        
        // Determine if calibration is needed
        let requiresCalibration = shouldRecalibrate(
            performanceScore: performanceScore,
            bottlenecks: bottlenecks
        )
        
        return ProfilingReport(
            sessionId: session.id,
            scanId: session.scanId,
            duration: session.duration,
            performanceScore: performanceScore,
            statistics: session.statistics,
            bottlenecks: bottlenecks,
            optimizationPaths: optimizationPaths,
            requiresCalibration: requiresCalibration
        )
    }
    
    private func generateOptimizationSuggestions(
        from report: ProfilingReport
    ) async throws -> [OptimizationSuggestion] {
        var suggestions: [OptimizationSuggestion] = []
        
        // Analyze performance patterns
        for bottleneck in report.bottlenecks {
            let suggestion = try await generateSuggestion(
                for: bottleneck,
                context: report
            )
            suggestions.append(suggestion)
        }
        
        // Prioritize suggestions
        suggestions.sort { $0.priority > $1.priority }
        
        return suggestions
    }
    
    private func updateCalibration(based report: ProfilingReport) async {
        do {
            let calibrationSession = try await calibrationManager.startCalibration(
                scanId: report.scanId,
                environment: report.configuration.environment
            )
            
            // Update calibration based on profiling data
            let measurements = generateCalibrationMeasurements(from: report)
            try await calibrationManager.updateCalibration(
                calibrationSession,
                measurements: measurements
            )
            
            try await calibrationManager.endCalibration(calibrationSession)
        } catch {
            logger.error("Failed to update calibration: \(error.localizedDescription)")
        }
    }
}

// MARK: - Types

extension ScanSessionProfiler {
    public struct ProfilingSession {
        let id: UUID
        let scanId: UUID
        let configuration: ScanConfiguration
        let startTime: Date
        var endTime: Date?
        var events: [EventRecord] = []
        var statistics = SessionStatistics()
        
        var duration: TimeInterval {
            guard let endTime = endTime else { return 0 }
            return endTime.timeIntervalSince(startTime)
        }
    }
    
    public struct ProfilingEvent {
        let name: String
        let type: EventType
        let significance: Significance
        var metadata: [String: Any] = [:]
        
        enum EventType {
            case scanStart
            case scanPause
            case scanResume
            case meshUpdate
            case qualityAdjustment
            case error
        }
        
        enum Significance: Int {
            case low = 0
            case medium = 1
            case high = 2
        }
    }
    
    struct EventRecord {
        let event: ProfilingEvent
        let timestamp: Date
        let metrics: PerformanceMetrics
    }
    
    public struct ProfilingReport {
        public let sessionId: UUID
        public let scanId: UUID
        public let duration: TimeInterval
        public let performanceScore: Float
        public let statistics: SessionStatistics
        public let bottlenecks: [PerformanceBottleneck]
        public let optimizationPaths: [OptimizationPath]
        public let requiresCalibration: Bool
    }
    
    struct SessionStatistics {
        private(set) var averageCPUUsage: Float = 0
        private(set) var averageGPUUsage: Float = 0
        private(set) var averageMemoryUsage: Float = 0
        private(set) var peakCPUUsage: Float = 0
        private(set) var peakGPUUsage: Float = 0
        private(set) var peakMemoryUsage: Float = 0
        private(set) var thermalEvents: Int = 0
        private var sampleCount: Int = 0
        
        mutating func update(with metrics: PerformanceMetrics) {
            let n = Float(sampleCount)
            averageCPUUsage = (averageCPUUsage * n + metrics.cpuUsage) / (n + 1)
            averageGPUUsage = (averageGPUUsage * n + metrics.gpuUsage) / (n + 1)
            averageMemoryUsage = (averageMemoryUsage * n + metrics.memoryUsage) / (n + 1)
            
            peakCPUUsage = max(peakCPUUsage, metrics.cpuUsage)
            peakGPUUsage = max(peakGPUUsage, metrics.gpuUsage)
            peakMemoryUsage = max(peakMemoryUsage, metrics.memoryUsage)
            
            if metrics.thermalState == .critical {
                thermalEvents += 1
            }
            
            sampleCount += 1
        }
    }
    
    struct PerformanceBottleneck {
        let type: BottleneckType
        let severity: Severity
        let impact: Float
        let recommendations: [String]
        
        enum BottleneckType {
            case cpu
            case gpu
            case memory
            case thermal
            case io
        }
        
        enum Severity: Int {
            case low = 0
            case medium = 1
            case high = 2
            case critical = 3
        }
    }
    
    struct OptimizationPath {
        let bottleneck: PerformanceBottleneck
        let steps: [OptimizationStep]
        let estimatedImprovement: Float
        
        struct OptimizationStep {
            let action: String
            let impact: Float
            let complexity: Int
        }
    }
    
    public struct OptimizationSuggestion {
        public let title: String
        public let description: String
        public let impact: Float
        public let priority: Int
        public let implementation: String
    }
    
    actor ProfileCache {
        private var sessions: [UUID: (ProfilingSession, ProfilingReport)] = [:]
        private let maxEntries = 10
        
        func add(session: ProfilingSession, report: ProfilingReport) {
            sessions[session.id] = (session, report)
            
            if sessions.count > maxEntries {
                let oldest = sessions.min { $0.value.0.startTime < $1.value.0.startTime }
                if let oldestId = oldest?.key {
                    sessions.removeValue(forKey: oldestId)
                }
            }
        }
        
        func get(sessionId: UUID) -> (ProfilingSession, ProfilingReport)? {
            return sessions[sessionId]
        }
    }
    
    enum ProfilingError: LocalizedError {
        case sessionNotFound
        case invalidMetrics
        case analysisFailure
        
        var errorDescription: String? {
            switch self {
            case .sessionNotFound:
                return "Profiling session not found"
            case .invalidMetrics:
                return "Invalid performance metrics"
            case .analysisFailure:
                return "Performance analysis failed"
            }
        }
    }
}

extension AnalyticsService.Event {
    static let profilingStarted = AnalyticsService.Event(name: "profiling_started")
    static let profilingCompleted = AnalyticsService.Event(name: "profiling_completed")
    static let significantPerformanceImpact = AnalyticsService.Event(name: "significant_performance_impact")
}