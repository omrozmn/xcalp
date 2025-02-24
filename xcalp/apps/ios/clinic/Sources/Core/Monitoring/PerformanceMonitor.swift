import Foundation
import os.log
import MetricKit
import Core.Configuration

public final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let metricQueue = DispatchQueue(label: "com.xcalp.performance", qos: .utility)
    
    private var metrics: [String: [TimeInterval]] = [:]
    private var startTimes: [String: DispatchTime] = [:]
    private var memoryWarningCount = 0
    
    // Performance thresholds from configuration
    private let maxProcessingTime = ScanningConfiguration.PerformanceThresholds.maxProcessingTime
    private let targetFrameRate = ScanningConfiguration.PerformanceThresholds.targetFrameRate
    private let maxMemoryUsage = ScanningConfiguration.PerformanceThresholds.maxMemoryUsage
    
    private let scanProcessingName = "scanProcessing"
    private let frameProcessingName = "frameProcessing"
    
    public func startMeasuring(_ operation: String, category: String) -> Int {
        let log = OSLog(subsystem: "com.xcalp.clinic", category: "Performance")
        let signpostID = OSSignpostID(log: log)
        
        let name: StaticString
        switch operation {
        case scanProcessingName:
            name = "scanProcessing"
        case frameProcessingName:
            name = "frameProcessing"
        default:
            name = "unknown"
        }
        
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        
        let key = "\(category).\(operation)"
        startTimes[key] = DispatchTime.now()
        
        return Int(signpostID.rawValue)
    }
    
    public func endMeasuring(_ operation: String, signpostID: Int, category: String) {
        let key = "\(category).\(operation)"
        guard let startTime = startTimes[key] else { return }
        
        let endTime = DispatchTime.now()
        let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        
        let log = OSLog(subsystem: "com.xcalp.clinic", category: "Performance")
        let name: StaticString
        switch operation {
        case scanProcessingName:
            name = "scanProcessing"
        case frameProcessingName:
            name = "frameProcessing"
        default:
            name = "unknown"
        }
        
        os_signpost(.end, log: log, name: name, signpostID: OSSignpostID(rawValue: UInt64(signpostID)))
        
        metricQueue.async {
            self.recordMetric(key: key, duration: duration)
            self.checkThresholds(operation: operation, duration: duration)
        }
    }
    
    private func recordMetric(key: String, duration: TimeInterval) {
        metrics[key, default: []].append(duration)
        
        // Keep only last 100 measurements
        if metrics[key]!.count > 100 {
            metrics[key]!.removeFirst()
        }
        
        // Calculate and log average
        if metrics[key]!.count >= 10 {
            let average = metrics[key]!.reduce(0, +) / Double(metrics[key]!.count)
            logger.info("\(key) average duration: \(average)s")
        }
    }
    
    private func checkThresholds(operation: String, duration: TimeInterval) {
        switch operation {
        case scanProcessingName:
            if duration > maxProcessingTime {
                logger.warning("Scan processing exceeded time threshold: \(duration)s")
                NotificationCenter.default.post(
                    name: Notification.Name("ScanningPerformanceWarning"),
                    object: nil,
                    userInfo: ["duration": duration]
                )
            }
            
        case frameProcessingName:
            let frameRate = 1.0 / duration
            if frameRate < Double(targetFrameRate) {
                logger.warning("Frame rate dropped below target: \(frameRate) FPS")
            }
            
        default:
            break
        }
    }
    
    public func reportMemoryWarning() {
        memoryWarningCount += 1
        
        if memoryWarningCount >= 3 {
            logger.warning("Frequent memory warnings detected")
            triggerMemoryOptimization()
        }
    }
    
    private func triggerMemoryOptimization() {
        NotificationCenter.default.post(
            name: Notification.Name("TriggerMemoryOptimization"),
            object: nil
        )
        
        // Reset counter after triggering optimization
        memoryWarningCount = 0
    }
    
    public func getMetrics() -> [String: (average: TimeInterval, peak: TimeInterval)] {
        var result: [String: (average: TimeInterval, peak: TimeInterval)] = [:]
        
        metricQueue.sync {
            for (key, measurements) in metrics {
                let average = measurements.reduce(0, +) / Double(measurements.count)
                let peak = measurements.max() ?? 0
                result[key] = (average, peak)
            }
        }
        
        return result
    }
}
