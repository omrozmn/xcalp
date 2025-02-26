import Foundation
import MetalKit
import os.log
import Combine
import MetricKit

@MainActor
public final class PerformanceMonitor: ObservableObject {
    public static let shared = PerformanceMonitor()
    
    // MARK: - Published Properties
    @Published private(set) var memoryUsage: UInt64 = 0
    @Published private(set) var frameRate: Double = 0
    @Published private(set) var gpuUtilization: Double = 0
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var isPerformanceLimited: Bool = false
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.performance", qos: .utility)
    private let signposter = OSSignposter(subsystem: "com.xcalp.clinic", category: "Performance")
    private var metalCommandQueue: MTLCommandQueue?
    private var updateTimer: Timer?
    private var metrics: [String: [TimeInterval]] = [:]
    private var thermalStateObserver: NSObjectProtocol?
    private var metricSubscriber: AnyCancellable?
    private var scanPhase: ScanningPhase = .initializing
    private var performanceHistory: [PerformanceSnapshot] = []
    
    // MARK: - Constants
    private let historyLimit = 100
    private let updateInterval: TimeInterval = 1.0
    
    private init() {
        setupMetalTracking()
        setupMetricKit()
        setupThermalMonitoring()
        startMonitoring()
    }
    
    // MARK: - Public Methods
    public func startMonitoring() {
        stopMonitoring() // Clean up any existing monitoring
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateMetrics()
            }
        }
        
        logger.info("Performance monitoring started")
    }
    
    public func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
        logger.info("Performance monitoring stopped")
    }
    
    public func updatePhase(_ phase: ScanningPhase) {
        scanPhase = phase
        logger.info("Scanning phase updated to: \(String(describing: phase))")
    }
    
    public func getPerformanceHistory() -> [PerformanceSnapshot] {
        return performanceHistory
    }
    
    public func reportResourceMetrics() -> ResourceMetrics {
        ResourceMetrics(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            gpuUtilization: gpuUtilization,
            frameRate: frameRate,
            thermalState: thermalState
        )
    }
    
    // MARK: - Private Methods
    private func setupMetalTracking() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Failed to create Metal device")
            return
        }
        metalCommandQueue = device.makeCommandQueue()
    }
    
    private func setupMetricKit() {
        metricSubscriber = MXMetricManager.shared.publisher
            .sink { [weak self] metrics in
                self?.processMetrics(metrics)
            }
        MXMetricManager.shared.add(self)
    }
    
    private func setupThermalMonitoring() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
            self?.checkThermalState()
        }
    }
    
    private func updateMetrics() async {
        await updateMemoryUsage()
        await updateCPUUsage()
        await updateGPUMetrics()
        checkPerformanceThresholds()
        recordSnapshot()
    }
    
    private func updateMemoryUsage() async {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            memoryUsage = info.resident_size
        }
    }
    
    private func updateCPUUsage() async {
        var totalUsagePercentage: Double = 0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if threadResult == KERN_SUCCESS, let threadList = threadList {
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var count = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                    }
                }
                
                if infoResult == KERN_SUCCESS {
                    let usage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                    totalUsagePercentage += usage
                }
            }
            
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }
        
        cpuUsage = min(totalUsagePercentage, 1.0)
    }
    
    private func updateGPUMetrics() async {
        guard let commandQueue = metalCommandQueue else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let start = CACurrentMediaTime()
        commandBuffer?.commit()
        commandBuffer?.waitUntil(Date().addingTimeInterval(0.001))
        let end = CACurrentMediaTime()
        
        frameRate = 1.0 / (end - start)
        gpuUtilization = min((end - start) / 0.016667, 1.0) // 60 FPS target
    }
    
    private func checkPerformanceThresholds() {
        let thresholds = AppConfiguration.Performance.Thresholds
        let wasLimited = isPerformanceLimited
        
        isPerformanceLimited = memoryUsage > thresholds.maxMemoryUsage ||
                             frameRate < thresholds.minFrameRate ||
                             gpuUtilization > thresholds.maxGPUUtilization ||
                             cpuUsage > thresholds.maxCPUUsage ||
                             thermalState == .serious
        
        if isPerformanceLimited != wasLimited {
            NotificationCenter.default.post(
                name: isPerformanceLimited ? .performanceLimitationBegan : .performanceLimitationEnded,
                object: self
            )
        }
    }
    
    private func checkThermalState() {
        if thermalState == .serious || thermalState == .critical {
            NotificationCenter.default.post(name: .thermalStateWarning, object: self)
        }
    }
    
    private func recordSnapshot() {
        let snapshot = PerformanceSnapshot(
            memoryUsage: memoryUsage,
            frameRate: frameRate,
            gpuUtilization: gpuUtilization,
            cpuUsage: cpuUsage,
            thermalState: thermalState,
            timestamp: Date()
        )
        
        performanceHistory.append(snapshot)
        if performanceHistory.count > historyLimit {
            performanceHistory.removeFirst()
        }
    }
    
    private func processMetrics(_ metrics: [MXMetric]) {
        // Process MetricKit metrics for additional insights
        metrics.forEach { metric in
            if let cpuMetric = metric as? MXCPUMetric {
                logger.debug("CPU time: \(cpuMetric.timeMetric.average)")
            }
            if let memoryMetric = metric as? MXMemoryMetric {
                logger.debug("Peak memory: \(memoryMetric.peakMemoryUsage.average)")
            }
        }
    }
}

// MARK: - Supporting Types
extension PerformanceMonitor {
    public struct ResourceMetrics {
        public let cpuUsage: Double
        public let memoryUsage: UInt64
        public let gpuUtilization: Double
        public let frameRate: Double
        public let thermalState: ProcessInfo.ThermalState
    }
    
    public struct PerformanceSnapshot {
        public let memoryUsage: UInt64
        public let frameRate: Double
        public let gpuUtilization: Double
        public let cpuUsage: Double
        public let thermalState: ProcessInfo.ThermalState
        public let timestamp: Date
    }
    
    public enum ScanningPhase {
        case initializing
        case lidar
        case photogrammetry
        case fusion
    }
}

// MARK: - Notifications
extension Notification.Name {
    public static let performanceLimitationBegan = Notification.Name("performanceLimitationBegan")
    public static let performanceLimitationEnded = Notification.Name("performanceLimitationEnded")
    public static let thermalStateWarning = Notification.Name("thermalStateWarning")
}
