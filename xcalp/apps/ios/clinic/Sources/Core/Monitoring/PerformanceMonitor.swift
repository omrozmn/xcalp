import Foundation
import Metal
import os.log

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let queue = DispatchQueue(label: "com.xcalp.performance", qos: .utility)
    private let signposter = OSSignposter()
    
    private var metrics: [String: PerformanceMetric] = [:]
    private var thresholds: [String: ResourceThreshold] = [:]
    private var intervalMetrics: [TimeInterval: [ResourceMetrics]] = [:]
    
    private init() {
        setupDefaultThresholds()
        startMonitoring()
    }
    
    func startMeasuring(_ operation: String, category: String = "default") -> OSSignpostID {
        let signpostID = signposter.makeSignpostID()
        signposter.emitEvent(category, "Start \(operation)")
        return signpostID
    }
    
    func endMeasuring(_ operation: String, signpostID: OSSignpostID, category: String = "default") {
        queue.async { [weak self] in
            self?.signposter.emitEvent(category, "End \(operation)")
            self?.updateMetrics(for: operation)
        }
    }
    
    func getCurrentMetrics() -> ResourceMetrics {
        queue.sync {
            ResourceMetrics(
                cpuUsage: currentCPUUsage(),
                memoryUsage: currentMemoryUsage(),
                gpuUtilization: currentGPUUtilization(),
                frameRate: calculateAverageFrameRate()
            )
        }
    }
    
    func setThreshold(_ threshold: ResourceThreshold, for metric: String) {
        queue.async { [weak self] in
            self?.thresholds[metric] = threshold
            self?.validateThresholds()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultThresholds() {
        thresholds = [
            "memory": ResourceThreshold(warning: 150_000_000, critical: 200_000_000),
            "cpu": ResourceThreshold(warning: 80, critical: 90),
            "gpu": ResourceThreshold(warning: 85, critical: 95),
            "framerate": ResourceThreshold(warning: 25, critical: 20)
        ]
    }
    
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.queue.async {
                self?.collectMetrics()
            }
        }
    }
    
    private func collectMetrics() {
        let current = ResourceMetrics(
            cpuUsage: currentCPUUsage(),
            memoryUsage: currentMemoryUsage(),
            gpuUtilization: currentGPUUtilization(),
            frameRate: calculateAverageFrameRate()
        )
        
        let timestamp = Date().timeIntervalSinceReferenceDate
        intervalMetrics[timestamp] = [current]
        
        // Clean up old metrics
        cleanupOldMetrics()
        
        // Validate thresholds
        validateThresholds()
    }
    
    private func currentCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var thread_list: thread_act_array_t?
        var thread_count: mach_msg_type_number_t = 0
        
        let task = mach_task_self_
        let kerr = task_threads(task, &thread_list, &thread_count)
        
        if kerr == KERN_SUCCESS, let threadList = thread_list {
            for i in 0..<Int(thread_count) {
                var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
                var thread_info_data = thread_basic_info()
                
                let _ = withUnsafeMutablePointer(to: &thread_info_data) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[i],
                                  thread_flavor_t(THREAD_BASIC_INFO),
                                  $0,
                                  &thread_info_count)
                    }
                }
                
                let threadBasicInfo = thread_info_data
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
            
            vm_deallocate(mach_task_self_,
                         vm_address_t(UInt(bitPattern: thread_list)),
                         vm_size_t(Int(thread_count) * MemoryLayout<thread_t>.stride))
        }
        
        return totalUsageOfCPU
    }
    
    private func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func currentGPUUtilization() -> Double {
        // This is a simplified implementation
        // In a real app, you'd want to use Metal's performance counters
        return 0.0
    }
    
    private func calculateAverageFrameRate() -> Double {
        guard let lastInterval = intervalMetrics.keys.max(),
              let metrics = intervalMetrics[lastInterval] else {
            return 0
        }
        
        return metrics.reduce(0.0) { $0 + $1.frameRate } / Double(metrics.count)
    }
    
    private func cleanupOldMetrics() {
        let currentTime = Date().timeIntervalSinceReferenceDate
        let oldThreshold = currentTime - 60 // Keep last minute of data
        
        intervalMetrics = intervalMetrics.filter { $0.key > oldThreshold }
    }
    
    private func validateThresholds() {
        let current = getCurrentMetrics()
        
        // Check memory usage
        if let threshold = thresholds["memory"] {
            if current.memoryUsage > threshold.critical {
                notifyCriticalThreshold("Memory usage critical: \(current.memoryUsage) bytes")
            } else if current.memoryUsage > threshold.warning {
                notifyWarningThreshold("Memory usage high: \(current.memoryUsage) bytes")
            }
        }
        
        // Check CPU usage
        if let threshold = thresholds["cpu"] {
            if current.cpuUsage > threshold.critical {
                notifyCriticalThreshold("CPU usage critical: \(current.cpuUsage)%")
            } else if current.cpuUsage > threshold.warning {
                notifyWarningThreshold("CPU usage high: \(current.cpuUsage)%")
            }
        }
        
        // Check frame rate
        if let threshold = thresholds["framerate"] {
            if current.frameRate < threshold.critical {
                notifyCriticalThreshold("Frame rate critical: \(current.frameRate) FPS")
            } else if current.frameRate < threshold.warning {
                notifyWarningThreshold("Frame rate low: \(current.frameRate) FPS")
            }
        }
    }
    
    private func notifyWarningThreshold(_ message: String) {
        logger.warning("\(message)")
        NotificationCenter.default.post(
            name: .performanceWarning,
            object: nil,
            userInfo: ["message": message]
        )
    }
    
    private func notifyCriticalThreshold(_ message: String) {
        logger.error("\(message)")
        NotificationCenter.default.post(
            name: .performanceCritical,
            object: nil,
            userInfo: ["message": message]
        )
    }
}

struct PerformanceMetric {
    let timestamp: TimeInterval
    let value: Double
    let category: String
}

struct ResourceThreshold {
    let warning: Double
    let critical: Double
}

struct ResourceMetrics {
    let cpuUsage: Double
    let memoryUsage: UInt64
    let gpuUtilization: Double
    let frameRate: Double
}

extension Notification.Name {
    static let performanceWarning = Notification.Name("performanceWarning")
    static let performanceCritical = Notification.Name("performanceCritical")
}
