import Foundation
import Metal
import MetalKit
import os.signpost

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let queue = DispatchQueue(label: "com.xcalp.performance", qos: .utility)
    private let log = OSLog(subsystem: "com.xcalp.clinic", category: "Performance")
    private let signpostID = OSSignpostID(log: .default)
    
    private var metrics: [String: [PerformanceMetrics]] = [:]
    private var currentOperations: [String: Date] = [:]
    private var memoryCheckTimer: Timer?
    
    private init() {
        setupMemoryMonitoring()
    }
    
    func beginOperation(_ name: String) {
        queue.async {
            self.currentOperations[name] = Date()
            os_signpost(.begin, log: self.log, name: "Operation", signpostID: self.signpostID, "%{public}s", name)
        }
    }
    
    func endOperation(_ name: String, gpuUtilization: Float? = nil) {
        queue.async {
            guard let startTime = self.currentOperations[name] else { return }
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            let memoryUsage = self.currentMemoryUsage()
            
            let metrics = PerformanceMetrics(
                timestamp: endTime,
                operation: name,
                duration: duration,
                memoryPeak: memoryUsage,
                gpuPeak: gpuUtilization ?? self.estimateGPUUtilization()
            )
            
            self.metrics[name, default: []].append(metrics)
            self.currentOperations.removeValue(forKey: name)
            
            os_signpost(.end, log: self.log, name: "Operation", signpostID: self.signpostID,
                       "Completed %{public}s - Duration: %.3f, Memory: %lld MB",
                       name, duration, memoryUsage / 1024 / 1024)
            
            // Check for performance issues
            self.analyzeMetrics(metrics)
        }
    }
    
    func getMetrics(for operation: String) -> [PerformanceMetrics] {
        queue.sync {
            return metrics[operation] ?? []
        }
    }
    
    func getAverageMetrics(for operation: String) -> PerformanceMetrics? {
        queue.sync {
            guard let operationMetrics = metrics[operation],
                  !operationMetrics.isEmpty else {
                return nil
            }
            
            let avgDuration = operationMetrics.reduce(0) { $0 + $1.duration } / Double(operationMetrics.count)
            let avgMemory = operationMetrics.reduce(0) { $0 + $1.memoryPeak } / Int64(operationMetrics.count)
            let avgGPU = operationMetrics.reduce(0) { $0 + $1.gpuPeak } / Float(operationMetrics.count)
            
            return PerformanceMetrics(
                timestamp: Date(),
                operation: operation,
                duration: avgDuration,
                memoryPeak: avgMemory,
                gpuPeak: avgGPU
            )
        }
    }
    
    func clearMetrics() {
        queue.async {
            self.metrics.removeAll()
        }
    }
    
    @objc private func checkMemoryUsage() {
        queue.async {
            let memoryUsage = self.currentMemoryUsage()
            let warningThreshold: Int64 = 384 * 1024 * 1024 // 384MB
            let criticalThreshold: Int64 = 512 * 1024 * 1024 // 512MB
            
            if memoryUsage > criticalThreshold {
                os_signpost(.event, log: self.log, name: "MemoryWarning",
                          "Critical memory usage: %lld MB", memoryUsage / 1024 / 1024)
                self.handleCriticalMemoryWarning()
            } else if memoryUsage > warningThreshold {
                os_signpost(.event, log: self.log, name: "MemoryWarning",
                          "High memory usage: %lld MB", memoryUsage / 1024 / 1024)
            }
        }
    }
    
    private func setupMemoryMonitoring() {
        memoryCheckTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(checkMemoryUsage),
            userInfo: nil,
            repeats: true
        )
    }
    
    private func currentMemoryUsage() -> Int64 {
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
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
    
    private func estimateGPUUtilization() -> Float {
        // This is a simplified estimation based on current operations
        let activeOperations = currentOperations.count
        return min(Float(activeOperations) * 0.2, 1.0)
    }
    
    private func analyzeMetrics(_ metrics: PerformanceMetrics) {
        // Check duration
        if metrics.duration > AnalysisConstants.maximumProcessingTime {
            os_signpost(.event, log: self.log, name: "PerformanceWarning",
                      "Long operation duration: %.3fs for %{public}s",
                      metrics.duration, metrics.operation)
        }
        
        // Check memory usage
        if metrics.memoryPeak > AnalysisConstants.maximumMemoryUsage {
            os_signpost(.event, log: self.log, name: "PerformanceWarning",
                      "High memory usage: %lld MB for %{public}s",
                      metrics.memoryPeak / 1024 / 1024, metrics.operation)
        }
        
        // Check GPU utilization
        if metrics.gpuPeak > 0.9 {
            os_signpost(.event, log: self.log, name: "PerformanceWarning",
                      "High GPU utilization: %.1f%% for %{public}s",
                      metrics.gpuPeak * 100, metrics.operation)
        }
    }
    
    private func handleCriticalMemoryWarning() {
        // Cancel non-essential operations
        let nonEssentialOperations = currentOperations.filter { operation, _ in
            !operation.contains("critical") && !operation.contains("essential")
        }
        
        for (operation, startTime) in nonEssentialOperations {
            let duration = Date().timeIntervalSince(startTime)
            os_signpost(.event, log: self.log, name: "OperationCancelled",
                      "Cancelled %{public}s after %.3fs due to memory pressure",
                      operation, duration)
            currentOperations.removeValue(forKey: operation)
        }
        
        // Clear metrics cache
        metrics.removeAll()
    }
}

// Extension for Metal performance monitoring
extension PerformanceMonitor {
    func monitorGPUCommand(
        _ commandBuffer: MTLCommandBuffer,
        operation: String
    ) {
        let startTime = Date()
        
        commandBuffer.addCompletedHandler { [weak self] buffer in
            guard let self = self else { return }
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            // Calculate GPU time from Metal timestamps
            let gpuStartTime = buffer.gpuStartTime
            let gpuEndTime = buffer.gpuEndTime
            let gpuDuration = gpuEndTime - gpuStartTime
            
            // Estimate GPU utilization
            let gpuUtilization = Float(gpuDuration / duration)
            
            self.queue.async {
                os_signpost(.event, log: self.log, name: "GPUOperation",
                          """
                          GPU Operation: %{public}s
                          CPU Time: %.3fs
                          GPU Time: %.3fs
                          Utilization: %.1f%%
                          """,
                          operation, duration, gpuDuration,
                          gpuUtilization * 100)
                
                // Update metrics
                if let startMetrics = self.metrics[operation]?.last {
                    let updatedMetrics = PerformanceMetrics(
                        timestamp: endTime,
                        operation: operation,
                        duration: duration,
                        memoryPeak: startMetrics.memoryPeak,
                        gpuPeak: gpuUtilization
                    )
                    self.metrics[operation, default: []].append(updatedMetrics)
                }
            }
        }
    }
    
    func reportGPUError(_ error: Error, operation: String) {
        queue.async {
            os_signpost(.event, log: self.log, name: "GPUError",
                      "GPU error in %{public}s: %{public}s",
                      operation, error.localizedDescription)
        }
    }
}

// Extension for async/await support
extension PerformanceMonitor {
    func measure<T>(_ operation: String, block: () async throws -> T) async throws -> T {
        beginOperation(operation)
        
        do {
            let result = try await block()
            endOperation(operation)
            return result
        } catch {
            endOperation(operation)
            throw error
        }
    }
}