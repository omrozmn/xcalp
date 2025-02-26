import Foundation
import Metal
import os.log

public actor ResourceMonitor {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ResourceMonitor")
    private let device: MTLDevice
    private let updateInterval: TimeInterval
    private var isMonitoring = false
    
    private var monitoringTask: Task<Void, Never>?
    private var metrics = CurrentValueSubject<ResourceMetrics, Never>(ResourceMetrics())
    private var warningThresholdReached = false
    private var criticalThresholdReached = false
    
    public init(
        device: MTLDevice,
        updateInterval: TimeInterval = 1.0
    ) {
        self.device = device
        self.updateInterval = updateInterval
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        monitoringTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isMonitoring {
                do {
                    let currentMetrics = try await self.gatherMetrics()
                    await self.analyzeMetrics(currentMetrics)
                    self.metrics.send(currentMetrics)
                    
                    try await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
                } catch {
                    self.logger.error("Error gathering metrics: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    public func currentMetrics() -> ResourceMetrics {
        return metrics.value
    }
    
    private func gatherMetrics() async throws -> ResourceMetrics {
        // CPU Usage
        let cpuUsage = ProcessInfo.processInfo.systemCpuUsage
        
        // Memory Usage
        let memoryUsage = ProcessInfo.processInfo.physicalMemory
        let availableMemory = ProcessInfo.processInfo.availableMemory
        
        // GPU Utilization
        let gpuUtilization = device.sampleGPUUtilization()
        
        // Thermal State
        let thermalState = ProcessInfo.processInfo.thermalState
        
        // Disk Space
        let diskSpace = try FileManager.default.volumeAvailableCapacity(for: .systemSize)
        let totalDiskSpace = try FileManager.default.volumeTotalCapacity(for: .systemSize)
        
        return ResourceMetrics(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            availableMemory: availableMemory,
            gpuUtilization: gpuUtilization,
            thermalState: thermalState,
            diskSpace: diskSpace,
            totalDiskSpace: totalDiskSpace,
            frameRate: metrics.value.frameRate
        )
    }
    
    private func analyzeMetrics(_ metrics: ResourceMetrics) async {
        let thresholds = AppConfiguration.Performance.Thresholds.self
        
        // Check for warning conditions
        let warningConditions = [
            metrics.cpuUsage >= thresholds.maxCPUUsage * 0.8,
            Double(metrics.memoryUsage) >= Double(thresholds.maxMemoryUsage) * 0.8,
            metrics.gpuUtilization >= thresholds.maxGPUUtilization * 0.8,
            metrics.thermalState == .serious,
            metrics.frameRate < thresholds.minFrameRate * 1.2
        ]
        
        // Check for critical conditions
        let criticalConditions = [
            metrics.cpuUsage >= thresholds.maxCPUUsage,
            Double(metrics.memoryUsage) >= Double(thresholds.maxMemoryUsage),
            metrics.gpuUtilization >= thresholds.maxGPUUtilization,
            metrics.thermalState == .critical,
            metrics.frameRate < thresholds.minFrameRate
        ]
        
        // Handle warning state
        if warningConditions.contains(true) && !warningThresholdReached {
            warningThresholdReached = true
            await handleWarningState(metrics)
        } else if !warningConditions.contains(true) {
            warningThresholdReached = false
        }
        
        // Handle critical state
        if criticalConditions.contains(true) && !criticalThresholdReached {
            criticalThresholdReached = true
            await handleCriticalState(metrics)
        } else if !criticalConditions.contains(true) {
            criticalThresholdReached = false
        }
        
        // Log metrics
        if warningThresholdReached || criticalThresholdReached {
            logMetrics(metrics)
        }
    }
    
    private func handleWarningState(_ metrics: ResourceMetrics) async {
        logger.warning("Resource warning threshold reached")
        
        // Notify observers
        NotificationCenter.default.post(
            name: .resourceWarningThresholdReached,
            object: nil,
            userInfo: ["metrics": metrics]
        )
        
        // Adjust quality settings
        await AdaptiveQualityManager.shared.updateQualitySettings(
            performance: metrics,
            environment: EnvironmentMetrics(
                lightingLevel: 1.0,
                motionStability: 1.0,
                surfaceComplexity: 0.5
            )
        )
    }
    
    private func handleCriticalState(_ metrics: ResourceMetrics) async {
        logger.error("Resource critical threshold reached")
        
        // Notify observers
        NotificationCenter.default.post(
            name: .resourceCriticalThresholdReached,
            object: nil,
            userInfo: ["metrics": metrics]
        )
        
        // Take immediate action
        if metrics.thermalState == .critical {
            NotificationCenter.default.post(name: .scanningNeedsCooldown, object: nil)
        }
        
        if Double(metrics.memoryUsage) >= Double(AppConfiguration.Performance.Thresholds.maxMemoryUsage) {
            NotificationCenter.default.post(name: .scanningNeedsMemoryCleanup, object: nil)
        }
    }
    
    private func logMetrics(_ metrics: ResourceMetrics) {
        let message = """
        Resource Metrics:
        CPU Usage: \(String(format: "%.1f%%", metrics.cpuUsage * 100))
        Memory Usage: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsage), countStyle: .memory))
        GPU Utilization: \(String(format: "%.1f%%", metrics.gpuUtilization * 100))
        Thermal State: \(metrics.thermalState.rawValue)
        Frame Rate: \(String(format: "%.1f fps", metrics.frameRate))
        """
        
        logger.info("\(message)")
    }
}

// MARK: - Supporting Types

public struct ResourceMetrics: Codable {
    public let timestamp: Date
    public let cpuUsage: Double
    public let memoryUsage: UInt64
    public let availableMemory: UInt64
    public let gpuUtilization: Double
    public let thermalState: ProcessInfo.ThermalState
    public let diskSpace: Int64
    public let totalDiskSpace: Int64
    public let frameRate: Double
    
    public init(
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsage: UInt64 = 0,
        availableMemory: UInt64 = 0,
        gpuUtilization: Double = 0,
        thermalState: ProcessInfo.ThermalState = .nominal,
        diskSpace: Int64 = 0,
        totalDiskSpace: Int64 = 0,
        frameRate: Double = 0
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.availableMemory = availableMemory
        self.gpuUtilization = gpuUtilization
        self.thermalState = thermalState
        self.diskSpace = diskSpace
        self.totalDiskSpace = totalDiskSpace
        self.frameRate = frameRate
    }
}

// MARK: - Extensions

extension ProcessInfo {
    func systemCpuUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if threadResult == KERN_SUCCESS, let threadList = threadList {
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
        
        return totalUsageOfCPU
    }
    
    var availableMemory: UInt64 {
        var pageSize: vm_size_t = 0
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        host_page_size(mach_host_self(), &pageSize)
        _ = withUnsafeMutablePointer(to: &vmStats) { vmStatsPointer in
            vmStatsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(mach_host_self(),
                                host_flavor_t(HOST_VM_INFO64),
                                pointer,
                                &count)
            }
        }
        
        let freeMemory = UInt64(vmStats.free_count) * UInt64(pageSize)
        return freeMemory
    }
}

extension MTLDevice {
    func sampleGPUUtilization() -> Double {
        // This is a simplified implementation
        // In a real app, you would use Metal's performance counters
        // or IOKit to get actual GPU utilization
        return 0.5
    }
}

extension Notification.Name {
    static let resourceWarningThresholdReached = Notification.Name("resourceWarningThresholdReached")
    static let resourceCriticalThresholdReached = Notification.Name("resourceCriticalThresholdReached")
    static let scanningNeedsCooldown = Notification.Name("scanningNeedsCooldown")
    static let scanningNeedsMemoryCleanup = Notification.Name("scanningNeedsMemoryCleanup")
}