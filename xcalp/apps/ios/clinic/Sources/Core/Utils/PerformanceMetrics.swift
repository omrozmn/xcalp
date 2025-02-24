// This file has been moved to Core/Services/Analytics/PerformanceMonitor.swift
// Please update any imports to use that file instead.
// This file will be removed in a future update.

@available(*, deprecated, message: "Use PerformanceMonitor from Core/Services/Analytics instead")
typealias PerformanceMetrics = PerformanceMonitor

import Foundation
import MetricKit

final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var frameRate: Double = 0
    @Published private(set) var processingTime: Double = 0
    
    private var timer: Timer?
    private let metricManager = MXMetricManager.shared
    
    private init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        metricManager.add(self)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        Task {
            await updateMemoryUsage()
            await updateFrameRate()
        }
    }
    
    private func updateMemoryUsage() async {
        // Get memory usage from process info
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            await MainActor.run {
                self.memoryUsage = usedMB
            }
        }
    }
    
    private func updateFrameRate() async {
        // TODO: Implement frame rate tracking
        // This should be done in the AR session delegate
    }
    
    func checkPerformanceRequirements() -> Bool {
        memoryUsage < 200 && // Less than 200MB
               frameRate > 30 && // Greater than 30fps
               processingTime < 5 // Less than 5s
    }
    
    func logPerformanceWarning() {
        if memoryUsage >= 200 {
            HIPAALogger.shared.log(type: .systemError,
                                 action: "High Memory Usage",
                                 userID: "SYSTEM",
                                 details: "Memory: \(memoryUsage)MB")
        }
        
        if frameRate <= 30 {
            HIPAALogger.shared.log(type: .systemError,
                                 action: "Low Frame Rate",
                                 userID: "SYSTEM",
                                 details: "FPS: \(frameRate)")
        }
    }
}

extension PerformanceMonitor: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Process MetricKit payloads
        for payload in payloads {
            // TODO: Process detailed metrics
        }
    }
    
    func receiveOptional(_ payloads: [MXDiagnosticPayload]) {
        // Handle diagnostic data
    }
}
