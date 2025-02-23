import Foundation
import FirebaseAnalytics
import Logging

/// Analytics service that handles usage tracking, error reporting, and performance monitoring
public final class AnalyticsService {
    public static let shared = AnalyticsService()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Analytics")
    private let performanceMonitor = PerformanceMonitor.shared
    
    private init() {}
    
    // MARK: - Analysis Events
    
    public func trackAnalysisStarted(_ type: AnalysisType) {
        Analytics.logEvent("analysis_started", parameters: [
            "type": type.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.info("Analysis started: \(type.rawValue)")
    }
    
    public func trackAnalysisCompleted(
        _ type: AnalysisType,
        duration: TimeInterval,
        results: [AnalysisResult]
    ) {
        Analytics.logEvent("analysis_completed", parameters: [
            "type": type.rawValue,
            "duration": duration,
            "result_count": results.count,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.info("Analysis completed: \(type.rawValue), duration: \(duration)")
    }
    
    public func trackAnalysisFailed(
        _ type: AnalysisType,
        error: Error
    ) {
        Analytics.logEvent("analysis_failed", parameters: [
            "type": type.rawValue,
            "error": error.localizedDescription,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.error("Analysis failed: \(type.rawValue), error: \(error.localizedDescription)")
    }
    
    public func trackAnalysisProgress(
        _ type: AnalysisType,
        progress: Double
    ) {
        Analytics.logEvent("analysis_progress", parameters: [
            "type": type.rawValue,
            "progress": progress,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.debug("Analysis progress: \(type.rawValue), progress: \(progress)")
    }
    
    public func trackUserInteraction(
        _ type: AnalysisType,
        action: String
    ) {
        Analytics.logEvent("analysis_interaction", parameters: [
            "type": type.rawValue,
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.debug("User interaction: \(type.rawValue), action: \(action)")
    }
    
    public func trackResourceUsage(_ type: AnalysisType) {
        let metrics = performanceMonitor.currentMetrics
        Analytics.logEvent("analysis_resources", parameters: [
            "type": type.rawValue,
            "memory_usage": metrics.memoryUsage,
            "cpu_usage": metrics.cpuUsage,
            "disk_usage": metrics.diskUsage,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.debug("Resource usage: \(type.rawValue), memory: \(metrics.memoryUsage), CPU: \(metrics.cpuUsage)")
    }
    
    // MARK: - Performance Events
    
    public func trackFrameRate(_ fps: Double) {
        Analytics.logEvent("frame_rate", parameters: [
            "fps": fps,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.debug("Frame rate: \(fps) FPS")
    }
    
    public func trackProcessingTime(
        _ operation: String,
        duration: TimeInterval
    ) {
        Analytics.logEvent("processing_time", parameters: [
            "operation": operation,
            "duration": duration,
            "timestamp": Date().timeIntervalSince1970
        ])
        logger.debug("Processing time: \(operation), duration: \(duration)")
    }
    
    // MARK: - Screen View Events
    
    /// Log a screen view event
    /// - Parameter screenName: Name of the screen being viewed
    public func logScreen(_ screenName: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName
        ])
        logger.info("Screen viewed: \(screenName)")
    }
    
    // MARK: - User Action Events
    
    /// Log a user action event
    /// - Parameters:
    ///   - action: The action performed
    ///   - category: Category of the action
    ///   - properties: Additional properties to log
    public func logAction(_ action: String, category: String, properties: [String: Any]? = nil) {
        var params: [String: Any] = [
            "action": action,
            "category": category
        ]
        properties?.forEach { params[$0] = $1 }
        
        Analytics.logEvent("user_action", parameters: params)
        logger.info("Action performed: \(action) in \(category)")
    }
    
    // MARK: - Scan Quality Events
    
    /// Log scan quality metrics
    /// - Parameters:
    ///   - quality: The scan quality level
    ///   - meshDensity: Density of the scanned mesh
    ///   - duration: Duration of the scan
    public func logScanQuality(quality: ScanningFeature.ScanQuality, meshDensity: Float, duration: TimeInterval) {
        Analytics.logEvent("scan_quality", parameters: [
            "quality": quality.rawValue,
            "mesh_density": meshDensity,
            "duration": duration
        ])
        logger.info("Scan completed: quality=\(quality), density=\(meshDensity), duration=\(duration)")
    }
    
    // MARK: - Performance Metrics Events
    
    /// Log performance metrics
    /// - Parameters:
    ///   - name: Name of the operation being measured
    ///   - duration: Duration of the operation
    ///   - memoryUsage: Peak memory usage during operation
    public func logPerformance(name: String, duration: TimeInterval, memoryUsage: Int64) {
        Analytics.logEvent("performance", parameters: [
            "operation": name,
            "duration": duration,
            "memory_usage": memoryUsage
        ])
        logger.info("Performance: \(name) took \(duration)s using \(memoryUsage) bytes")
    }
    
    // MARK: - Error Events
    
    /// Log error events
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - severity: Severity level of the error
    ///   - context: Additional context about the error
    public func logError(_ error: Error, severity: ErrorSeverity, context: [String: Any]? = nil) {
        var params: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription,
            "severity": severity.rawValue
        ]
        context?.forEach { params[$0] = $1 }
        
        Analytics.logEvent("error", parameters: params)
        logger.error("Error occurred: \(error.localizedDescription), severity=\(severity)")
        
        if severity == .critical {
            // Send critical errors to crash reporting
            Crashlytics.crashlytics().record(error: error)
        }
    }
    
    // MARK: - HIPAA Events
    
    /// Log HIPAA-relevant events for compliance
    /// - Parameters:
    ///   - action: The action performed
    ///   - resourceType: Type of resource accessed
    ///   - resourceId: Identifier of the resource
    ///   - userId: ID of the user performing the action
    public func logHIPAAEvent(action: HIPAAAction, resourceType: String, resourceId: String, userId: String) {
        let params: [String: Any] = [
            "action": action.rawValue,
            "resource_type": resourceType,
            "resource_id": resourceId,
            "user_id": userId,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        Analytics.logEvent("hipaa_audit", parameters: params)
        logger.notice("HIPAA Event: \(action.rawValue) on \(resourceType):\(resourceId) by \(userId)")
    }
}

// MARK: - Supporting Types
extension AnalyticsService {
    public enum ErrorSeverity: String {
        case low
        case medium
        case high
        case critical
    }
    
    public enum HIPAAAction: String {
        case view = "VIEW"
        case create = "CREATE"
        case modify = "MODIFY"
        case delete = "DELETE"
        case export = "EXPORT"
        case print = "PRINT"
    }
}

// MARK: - Dependency Interface

public struct AnalyticsClient {
    public var trackAnalysisStarted: (AnalysisType) -> Void
    public var trackAnalysisCompleted: (AnalysisType, TimeInterval, [AnalysisResult]) -> Void
    public var trackAnalysisFailed: (AnalysisType, Error) -> Void
    public var trackAnalysisProgress: (AnalysisType, Double) -> Void
    public var trackUserInteraction: (AnalysisType, String) -> Void
    public var trackResourceUsage: (AnalysisType) -> Void
    public var trackFrameRate: (Double) -> Void
    public var trackProcessingTime: (String, TimeInterval) -> Void
    
    public init(
        trackAnalysisStarted: @escaping (AnalysisType) -> Void,
        trackAnalysisCompleted: @escaping (AnalysisType, TimeInterval, [AnalysisResult]) -> Void,
        trackAnalysisFailed: @escaping (AnalysisType, Error) -> Void,
        trackAnalysisProgress: @escaping (AnalysisType, Double) -> Void,
        trackUserInteraction: @escaping (AnalysisType, String) -> Void,
        trackResourceUsage: @escaping (AnalysisType) -> Void,
        trackFrameRate: @escaping (Double) -> Void,
        trackProcessingTime: @escaping (String, TimeInterval) -> Void
    ) {
        self.trackAnalysisStarted = trackAnalysisStarted
        self.trackAnalysisCompleted = trackAnalysisCompleted
        self.trackAnalysisFailed = trackAnalysisFailed
        self.trackAnalysisProgress = trackAnalysisProgress
        self.trackUserInteraction = trackUserInteraction
        self.trackResourceUsage = trackResourceUsage
        self.trackFrameRate = trackFrameRate
        self.trackProcessingTime = trackProcessingTime
    }
}

extension AnalyticsClient {
    public static let live = Self(
        trackAnalysisStarted: { AnalyticsService.shared.trackAnalysisStarted($0) },
        trackAnalysisCompleted: { AnalyticsService.shared.trackAnalysisCompleted($0, duration: $1, results: $2) },
        trackAnalysisFailed: { AnalyticsService.shared.trackAnalysisFailed($0, error: $1) },
        trackAnalysisProgress: { AnalyticsService.shared.trackAnalysisProgress($0, progress: $1) },
        trackUserInteraction: { AnalyticsService.shared.trackUserInteraction($0, action: $1) },
        trackResourceUsage: { AnalyticsService.shared.trackResourceUsage($0) },
        trackFrameRate: { AnalyticsService.shared.trackFrameRate($0) },
        trackProcessingTime: { AnalyticsService.shared.trackProcessingTime($0, duration: $1) }
    )
    
    public static let test = Self(
        trackAnalysisStarted: { _ in },
        trackAnalysisCompleted: { _, _, _ in },
        trackAnalysisFailed: { _, _ in },
        trackAnalysisProgress: { _, _ in },
        trackUserInteraction: { _, _ in },
        trackResourceUsage: { _ in },
        trackFrameRate: { _ in },
        trackProcessingTime: { _, _ in }
    )
}