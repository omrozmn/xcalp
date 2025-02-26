import Foundation

class AnalyticsService {
    static let shared = AnalyticsService()
    private let storage = SecureStorage.shared
    
    // Event categories
    private enum Category: String {
        case workflow = "workflow"
        case cultural = "cultural"
        case compliance = "compliance"
        case scanning = "scanning"
        case error = "error"
        case security = "security"
        case performance = "performance"
    }
    
    private var metrics: [String: Any] = [:]
    private var eventBuffer: [AnalyticsEvent] = []
    private let bufferLimit = 100
    private let eventQueue = DispatchQueue(label: "com.xcalp.clinic.analytics")
    
    private init() {
        setupPeriodicFlush()
    }
    
    // MARK: - Public Interface
    
    func trackWorkflowStep(_ step: WorkflowStep, region: Region, success: Bool) {
        let event = AnalyticsEvent(
            category: .workflow,
            action: "step_completion",
            label: String(describing: step),
            value: success ? 1 : 0,
            metadata: [
                "region": region.rawValue,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
        logEvent(event)
    }
    
    func trackCulturalAnalysis(_ result: CulturalAnalysisResult) {
        let event = AnalyticsEvent(
            category: .cultural,
            action: "analysis_complete",
            label: result.region.rawValue,
            value: Int(result.conformanceScore * 100),
            metadata: [
                "pattern_match": result.recommendations.isEmpty,
                "religion_considered": !result.religiousConsiderations.isEmpty,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
        logEvent(event)
    }
    
    func trackComplianceValidation(_ rule: ComplianceRule, success: Bool) {
        let event = AnalyticsEvent(
            category: .compliance,
            action: "validation",
            label: String(describing: rule),
            value: success ? 1 : 0,
            metadata: [
                "timestamp": Date().timeIntervalSince1970
            ]
        )
        logEvent(event)
    }
    
    func trackScanQuality(_ scan: ScanData) {
        let event = AnalyticsEvent(
            category: .scanning,
            action: "quality_check",
            label: scan.id.uuidString,
            value: Int(scan.qualityScore * 100),
            metadata: [
                "lighting_score": scan.lightingScore,
                "point_density": scan.pointDensity,
                "is_calibrated": scan.isCalibrated,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
        logEvent(event)
    }
    
    func trackCriticalError(_ error: Error) {
        let event = AnalyticsEvent(
            category: .error,
            action: "critical_error",
            label: String(describing: type(of: error)),
            value: 0,
            metadata: [
                "description": error.localizedDescription,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
        logEvent(event)
    }
    
    func trackError(_ error: Error, severity: ErrorSeverity = .medium, context: [String: Any] = [:]) {
        var metadata = context
        metadata["timestamp"] = Date().timeIntervalSince1970
        metadata["severity"] = severity.rawValue
        
        let event = AnalyticsEvent(
            category: .error,
            action: "error",
            label: String(describing: type(of: error)),
            value: severity.rawValue,
            metadata: metadata
        )
        logEvent(event)
    }
    
    func updateMetric(_ name: String, value: Double) {
        eventQueue.async {
            self.metrics[name] = value
        }
    }
    
    func incrementMetric(_ name: String, by value: Double = 1.0) {
        eventQueue.async {
            let currentValue = (self.metrics[name] as? Double) ?? 0.0
            self.metrics[name] = currentValue + value
        }
    }
    
    // MARK: - Private Methods
    
    private func logEvent(_ event: AnalyticsEvent) {
        eventQueue.async {
            self.eventBuffer.append(event)
            
            if self.eventBuffer.count >= self.bufferLimit {
                self.flushEvents()
            }
        }
    }
    
    private func setupPeriodicFlush() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.flushEvents()
        }
    }
    
    private func flushEvents() {
        guard !eventBuffer.isEmpty else { return }
        
        let eventsToFlush = eventBuffer
        eventBuffer.removeAll()
        
        Task {
            do {
                try await storeEvents(eventsToFlush)
            } catch {
                Logger.shared.error("Failed to flush analytics events: \(error.localizedDescription)")
                // Re-add events to buffer if storage failed
                eventQueue.async {
                    self.eventBuffer.insert(contentsOf: eventsToFlush, at: 0)
                }
            }
        }
    }
    
    private func storeEvents(_ events: [AnalyticsEvent]) async throws {
        // Store events with expiration to manage storage space
        try await storage.store(
            events,
            forKey: "analytics_events_\(Date().timeIntervalSince1970)",
            expires: .days(30)
        )
    }
}

// MARK: - Supporting Types

struct AnalyticsEvent: Codable {
    let category: AnalyticsService.Category
    let action: String
    let label: String
    let value: Int
    let metadata: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case category, action, label, value, metadata
    }
    
    init(category: AnalyticsService.Category, action: String, label: String, value: Int, metadata: [String: Any]) {
        self.category = category
        self.action = action
        self.label = label
        self.value = value
        self.metadata = metadata
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(action, forKey: .action)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
        try container.encode(metadata.compactMapValues { $0 as? String }, forKey: .metadata)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = AnalyticsService.Category(rawValue: try container.decode(String.self, forKey: .category))!
        action = try container.decode(String.self, forKey: .action)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(Int.self, forKey: .value)
        metadata = try container.decode([String: String].self, forKey: .metadata)
    }
}

enum ErrorSeverity: Int {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    
    var rawValue: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

extension AnalyticsService {
    func trackWorkflowPerformance(identifier: String, metrics: [String: Double]) {
        let event = AnalyticsEvent(
            category: .performance,
            action: "workflow_metrics",
            label: identifier,
            value: Int(metrics["duration"] ?? 0),
            metadata: metrics.mapValues { String($0) }
        )
        logEvent(event)
    }
    
    func trackPerformanceIssue(identifier: String, metric: MetricType, value: Double, threshold: Double) {
        let event = AnalyticsEvent(
            category: .performance,
            action: "threshold_exceeded",
            label: identifier,
            value: Int(value),
            metadata: [
                "metric_type": String(describing: metric),
                "threshold": String(threshold),
                "value": String(value),
                "timestamp": String(Date().timeIntervalSince1970)
            ]
        )
        logEvent(event)
    }
    
    @available(iOS 13.0, *)
    func trackMetricKitPayload(_ payload: MXMetricPayload) {
        let metrics = extractMetrics(from: payload)
        
        let event = AnalyticsEvent(
            category: .performance,
            action: "metrickit_metrics",
            label: payload.timeStampEnd.description,
            value: 0,
            metadata: metrics
        )
        logEvent(event)
    }
    
    @available(iOS 13.0, *)
    func trackDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        let diagnostics = extractDiagnostics(from: payload)
        
        let event = AnalyticsEvent(
            category: .performance,
            action: "metrickit_diagnostics",
            label: payload.timeStampEnd.description,
            value: 0,
            metadata: diagnostics
        )
        logEvent(event)
    }
    
    @available(iOS 13.0, *)
    private func extractMetrics(from payload: MXMetricPayload) -> [String: String] {
        var metrics: [String: String] = [:]
        
        if let animationMetrics = payload.animationMetrics {
            metrics["scroll_hitch_time"] = String(animationMetrics.scrollHitchTimeRatio)
        }
        
        if let memoryMetrics = payload.memoryMetrics {
            metrics["peak_memory"] = String(memoryMetrics.peakMemoryUsage)
            metrics["avg_suspended_memory"] = String(memoryMetrics.averageSuspendedMemory)
        }
        
        if let applicationLaunchMetrics = payload.applicationLaunchMetrics {
            metrics["launch_time"] = String(applicationLaunchMetrics.timeToFirstDraw.duration)
        }
        
        return metrics
    }
    
    @available(iOS 13.0, *)
    private func extractDiagnostics(from payload: MXDiagnosticPayload) -> [String: String] {
        var diagnostics: [String: String] = [:]
        
        if let cpuExceptions = payload.cpuExceptionDiagnostics {
            diagnostics["cpu_exceptions"] = String(cpuExceptions.count)
        }
        
        if let diskWriteExceptions = payload.diskWriteExceptionDiagnostics {
            diagnostics["disk_write_exceptions"] = String(diskWriteExceptions.count)
        }
        
        if let hangDiagnostics = payload.hangDiagnostics {
            diagnostics["hangs"] = String(hangDiagnostics.count)
        }
        
        return diagnostics
    }
}

extension AnalyticsService.Category {
    static let performance = AnalyticsService.Category(rawValue: "performance")
}