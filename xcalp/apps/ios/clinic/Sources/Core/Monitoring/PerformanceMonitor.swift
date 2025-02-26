import Foundation
import MetricKit
import os.log

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let analytics = AnalyticsService.shared
    private let queue = DispatchQueue(label: "com.xcalp.clinic.performance")
    
    private var measurements: [String: PerformanceMeasurement] = [:]
    private var thresholds: [MetricType: Double] = [
        .processingTime: 5.0,    // 5 seconds
        .memoryUsage: 750 * 1024 * 1024,  // 750MB
        .diskUsage: 100 * 1024 * 1024,    // 100MB
        .networkLatency: 0.5     // 500ms
    ]
    
    private init() {
        setupMetricSubscriber()
    }
    
    // MARK: - Public Interface
    
    func startMeasuring(_ identifier: String) {
        queue.async {
            let measurement = PerformanceMeasurement(
                identifier: identifier,
                startTime: Date(),
                initialMemory: self.currentMemoryUsage
            )
            self.measurements[identifier] = measurement
        }
    }
    
    func stopMeasuring(_ identifier: String) {
        queue.async {
            guard let measurement = self.measurements[identifier] else { return }
            
            let duration = Date().timeIntervalSince(measurement.startTime)
            let memoryDelta = self.currentMemoryUsage - measurement.initialMemory
            
            // Log metrics
            self.logMetrics(
                identifier: identifier,
                duration: duration,
                memoryDelta: memoryDelta
            )
            
            // Track in analytics
            self.trackMetrics(
                identifier: identifier,
                duration: duration,
                memoryDelta: memoryDelta
            )
            
            // Remove measurement
            self.measurements.removeValue(forKey: identifier)
            
            // Check thresholds
            self.checkThresholds(
                identifier: identifier,
                duration: duration,
                memoryDelta: memoryDelta
            )
        }
    }
    
    func setThreshold(_ value: Double, for metricType: MetricType) {
        queue.async {
            self.thresholds[metricType] = value
        }
    }
    
    func getCurrentMetrics() -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        queue.sync {
            metrics["memory_usage"] = currentMemoryUsage
            metrics["disk_usage"] = currentDiskUsage
            metrics["network_latency"] = averageNetworkLatency
            
            for (identifier, measurement) in measurements {
                metrics["\(identifier)_duration"] = Date().timeIntervalSince(measurement.startTime)
            }
        }
        
        return metrics
    }
    
    // MARK: - Private Methods
    
    private func setupMetricSubscriber() {
        if #available(iOS 13.0, *) {
            MXMetricManager.shared.add(self)
        }
    }
    
    private func logMetrics(identifier: String, duration: TimeInterval, memoryDelta: Double) {
        logger.info("""
            Performance metrics for \(identifier):
            Duration: \(duration)s
            Memory Delta: \(formatBytes(memoryDelta))
            """)
    }
    
    private func trackMetrics(identifier: String, duration: TimeInterval, memoryDelta: Double) {
        analytics.trackWorkflowPerformance(
            identifier: identifier,
            metrics: [
                "duration": duration,
                "memory_delta": memoryDelta,
                "total_memory": currentMemoryUsage,
                "disk_usage": currentDiskUsage,
                "network_latency": averageNetworkLatency
            ]
        )
    }
    
    private func checkThresholds(identifier: String, duration: TimeInterval, memoryDelta: Double) {
        if duration > thresholds[.processingTime] ?? Double.infinity {
            reportThresholdExceeded(
                identifier: identifier,
                metric: .processingTime,
                value: duration,
                threshold: thresholds[.processingTime] ?? 0
            )
        }
        
        if currentMemoryUsage > thresholds[.memoryUsage] ?? Double.infinity {
            reportThresholdExceeded(
                identifier: identifier,
                metric: .memoryUsage,
                value: currentMemoryUsage,
                threshold: thresholds[.memoryUsage] ?? 0
            )
        }
    }
    
    private func reportThresholdExceeded(identifier: String, metric: MetricType, value: Double, threshold: Double) {
        logger.warning("""
            Performance threshold exceeded:
            Operation: \(identifier)
            Metric: \(metric)
            Value: \(value)
            Threshold: \(threshold)
            """)
        
        analytics.trackPerformanceIssue(
            identifier: identifier,
            metric: metric,
            value: value,
            threshold: threshold
        )
    }
    
    private var currentMemoryUsage: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size)
    }
    
    private var currentDiskUsage: Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) else {
            return 0
        }
        return attrs[.systemFreeSize] as? Double ?? 0
    }
    
    private var averageNetworkLatency: Double {
        // Implementation would track and average network request latencies
        return 0.0
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types

struct PerformanceMeasurement {
    let identifier: String
    let startTime: Date
    let initialMemory: Double
}

enum MetricType {
    case processingTime
    case memoryUsage
    case diskUsage
    case networkLatency
}

// MARK: - MetricKit Integration

@available(iOS 13.0, *)
extension PerformanceMonitor: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Process MetricKit payloads
            analytics.trackMetricKitPayload(payload)
        }
    }
    
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Process diagnostic payloads
            analytics.trackDiagnosticPayload(payload)
        }
    }
}
