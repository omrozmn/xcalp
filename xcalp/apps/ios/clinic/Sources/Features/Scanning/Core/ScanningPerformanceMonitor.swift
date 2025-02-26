import Foundation
import MetricKit

public struct ScanningMetrics {
    let fps: Double
    let memoryUsage: Double
    let cpuUsage: Double
    let thermalState: ProcessInfo.ThermalState
    let latency: TimeInterval
    let pointsPerSecond: Int
    let processingTime: TimeInterval
    let batteryLevel: Float
    
    var isPerformanceAcceptable: Bool {
        return fps >= 30 &&
               memoryUsage < 0.8 &&
               cpuUsage < 0.9 &&
               thermalState != .critical &&
               latency < 0.1
    }
}

public class ScanningPerformanceMonitor {
    private let updateInterval: TimeInterval = 1.0
    private var frameCount: Int = 0
    private var lastUpdateTime: TimeInterval = 0
    private var processingTimes: [TimeInterval] = []
    private var pointCounts: [Int] = []
    
    private let metricsHandler: MXMetricManager
    private let thermalStateHandler: ProcessInfo
    private var performanceTimer: Timer?
    
    private var onMetricsUpdate: ((ScanningMetrics) -> Void)?
    
    public init(onMetricsUpdate: @escaping (ScanningMetrics) -> Void) {
        self.onMetricsUpdate = onMetricsUpdate
        self.metricsHandler = MXMetricManager.shared
        self.thermalStateHandler = ProcessInfo.processInfo
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        performanceTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    public func recordFrame() {
        frameCount += 1
    }
    
    public func recordProcessingTime(_ time: TimeInterval) {
        processingTimes.append(time)
        if processingTimes.count > 60 {
            processingTimes.removeFirst()
        }
    }
    
    public func recordPointCount(_ count: Int) {
        pointCounts.append(count)
        if pointCounts.count > 60 {
            pointCounts.removeFirst()
        }
    }
    
    private func updateMetrics() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastUpdateTime
        
        // Calculate FPS
        let fps = Double(frameCount) / deltaTime
        frameCount = 0
        lastUpdateTime = currentTime
        
        // Get system metrics
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        let thermalState = thermalStateHandler.thermalState
        
        // Calculate processing metrics
        let averageLatency = processingTimes.reduce(0, +) / Double(max(1, processingTimes.count))
        let pointsPerSecond = Int(Double(pointCounts.last ?? 0) / deltaTime)
        let averageProcessingTime = processingTimes.reduce(0, +) / Double(max(1, processingTimes.count))
        
        let metrics = ScanningMetrics(
            fps: fps,
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            thermalState: thermalState,
            latency: averageLatency,
            pointsPerSecond: pointsPerSecond,
            processingTime: averageProcessingTime,
            batteryLevel: UIDevice.current.batteryLevel
        )
        
        onMetricsUpdate?(metrics)
    }
    
    private func getMemoryUsage() -> Double {
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
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size)
            let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
            return usedMemory / totalMemory
        }
        
        return 0
    }
    
    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if threadResult == KERN_SUCCESS,
           let threadList = threadList {
            for index in 0..<threadCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[Int(index)],
                                  thread_flavor_t(THREAD_BASIC_INFO),
                                  $0,
                                  &threadInfoCount)
                    }
                }
                
                if infoResult == KERN_SUCCESS {
                    let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                    totalUsageOfCPU += cpuUsage
                }
            }
            
            vm_deallocate(mach_task_self_,
                         vm_address_t(UInt(bitPattern: threadList)),
                         vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        
        return min(totalUsageOfCPU, 1.0)
    }
    
    deinit {
        performanceTimer?.invalidate()
    }
}