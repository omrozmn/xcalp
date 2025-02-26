import Foundation
import Metal
import QuartzCore

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var measurements: [String: [Measurement]] = [:]
    private var activeTimers: [String: CFTimeInterval] = [:]
    private var memoryHighWatermark: UInt64 = 0
    private let memoryManager = MemoryPressureManager()
    
    struct Measurement {
        let duration: CFTimeInterval
        let memoryUsage: UInt64
        let timestamp: Date
        let metadata: [String: Any]
    }
    
    func startMeasuring(_ identifier: String, metadata: [String: Any] = [:]) {
        activeTimers[identifier] = CACurrentMediaTime()
    }
    
    func stopMeasuring(_ identifier: String, additionalMetadata: [String: Any] = [:]) -> Measurement {
        guard let startTime = activeTimers.removeValue(forKey: identifier) else {
            fatalError("No active timer found for identifier: \(identifier)")
        }
        
        let duration = CACurrentMediaTime() - startTime
        let currentMemory = memoryManager.currentMemoryUsage()
        memoryHighWatermark = max(memoryHighWatermark, currentMemory)
        
        let measurement = Measurement(
            duration: duration,
            memoryUsage: currentMemory,
            timestamp: Date(),
            metadata: additionalMetadata
        )
        
        measurements[identifier, default: []].append(measurement)
        return measurement
    }
    
    func getStatistics(for identifier: String) -> PerformanceStatistics {
        guard let measurements = measurements[identifier] else {
            return PerformanceStatistics()
        }
        
        let durations = measurements.map { $0.duration }
        let memoryUsages = measurements.map { $0.memoryUsage }
        
        return PerformanceStatistics(
            averageDuration: durations.reduce(0, +) / Double(durations.count),
            minDuration: durations.min() ?? 0,
            maxDuration: durations.max() ?? 0,
            averageMemory: memoryUsages.reduce(0, +) / UInt64(memoryUsages.count),
            peakMemory: memoryHighWatermark,
            sampleCount: measurements.count
        )
    }
    
    func generateReport() -> PerformanceReport {
        var report = PerformanceReport()
        
        for (identifier, measurements) in measurements {
            let stats = getStatistics(for: identifier)
            report.addMetric(identifier: identifier, statistics: stats)
        }
        
        return report
    }
    
    func reset() {
        measurements.removeAll()
        activeTimers.removeAll()
        memoryHighWatermark = 0
    }
}

struct PerformanceStatistics {
    var averageDuration: CFTimeInterval = 0
    var minDuration: CFTimeInterval = 0
    var maxDuration: CFTimeInterval = 0
    var averageMemory: UInt64 = 0
    var peakMemory: UInt64 = 0
    var sampleCount: Int = 0
    
    var durationVariance: CFTimeInterval {
        guard sampleCount > 1 else { return 0 }
        return maxDuration - minDuration
    }
    
    var isAcceptable: Bool {
        return averageDuration <= TestConfiguration.maxProcessingTime &&
               peakMemory <= UInt64(TestConfiguration.maxMemoryUsage)
    }
}

struct PerformanceReport {
    private var metrics: [String: PerformanceStatistics] = [:]
    
    mutating func addMetric(identifier: String, statistics: PerformanceStatistics) {
        metrics[identifier] = statistics
    }
    
    var summary: String {
        return metrics.map { identifier, stats in
            """
            \(identifier):
                Average Duration: \(String(format: "%.3f", stats.averageDuration))s
                Memory Usage: \(ByteCountFormatter.string(fromByteCount: Int64(stats.averageMemory), countStyle: .memory))
                Peak Memory: \(ByteCountFormatter.string(fromByteCount: Int64(stats.peakMemory), countStyle: .memory))
                Samples: \(stats.sampleCount)
            """
        }.joined(separator: "\n\n")
    }
    
    var allMetricsAcceptable: Bool {
        return metrics.values.allSatisfy { $0.isAcceptable }
    }
}

private final class MemoryPressureManager {
    func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        
        return UInt64(info.resident_size)
    }
}