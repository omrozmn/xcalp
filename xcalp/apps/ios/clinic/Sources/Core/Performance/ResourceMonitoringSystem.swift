import Darwin
import Foundation
import Metal
import MetalPerformanceShaders

class ResourceMonitoringSystem {
    private var cpuInfo: processor_info_array_t?
    private var prevCPUInfo: processor_info_array_t?
    private var numCPUInfo: mach_msg_type_number_t = 0
    private var numPrevCPUInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    #if os(iOS)
    private let loadInfoCount: natural_t = UInt32(HOST_CPU_LOAD_INFO_COUNT)
    #endif
    
    init() {
        #if os(iOS)
        var size = MemoryLayout<integer_t>.stride * Int(HOST_VM_INFO64_COUNT)
        #endif
        host_processor_info(mach_host_self(),
                          PROCESSOR_CPU_LOAD_INFO,
                          &numCPUs,
                          &cpuInfo,
                          &numCPUInfo)
    }
    
    func getCPUUsage() -> Float {
        var totalUsage: Float = 0.0
        
        // Get the latest CPU info
        let result = host_processor_info(mach_host_self(),
                                       PROCESSOR_CPU_LOAD_INFO,
                                       &numCPUs,
                                       &cpuInfo,
                                       &numCPUInfo)
        
        if result == KERN_SUCCESS {
            if let prevCPUInfo = prevCPUInfo {
                // Calculate CPU usage percentage for each core
                for i in 0..<Int(numCPUs) {
                    let inUse = Float(cpuInfo![i * Int(CPU_STATE_MAX) + Int(CPU_STATE_USER)] -
                                    prevCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_USER)] +
                                    cpuInfo![i * Int(CPU_STATE_MAX) + Int(CPU_STATE_SYSTEM)] -
                                    prevCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_SYSTEM)] +
                                    cpuInfo![i * Int(CPU_STATE_MAX) + Int(CPU_STATE_NICE)] -
                                    prevCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_NICE)])
                    
                    let total = inUse + Float(cpuInfo![i * Int(CPU_STATE_MAX) + Int(CPU_STATE_IDLE)] -
                                            prevCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_IDLE)])
                    
                    totalUsage += inUse / total
                }
                
                totalUsage /= Float(numCPUs)
            }
            
            // Store current CPU info for next iteration
            if let prevCPUInfo = self.prevCPUInfo {
                prevCPUInfo.deallocate()
            }
            
            self.prevCPUInfo = cpuInfo
            self.numPrevCPUInfo = numCPUInfo
            
            cpuInfo = nil
            numCPUInfo = 0
        }
        
        return min(max(totalUsage, 0), 1)
    }
    
    func getMemoryUsage() -> Float {
        var pagesize: vm_size_t = 0
        
        let hostPort: mach_port_t = mach_host_self()
        var hostSize: mach_msg_type_number_t = mach_msg_type_number_t(MemoryLayout<vm_statistics_data_t>.stride / MemoryLayout<integer_t>.stride)
        var hostInfo64: vm_statistics64 = vm_statistics64()
        
        host_page_size(hostPort, &pagesize)
        
        let status = withUnsafeMutablePointer(to: &hostInfo64) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics64(hostPort,
                                HOST_VM_INFO64,
                                $0,
                                &hostSize)
            }
        }
        
        if status == KERN_SUCCESS {
            let total = Float(hostInfo64.wire_count +
                            hostInfo64.active_count +
                            hostInfo64.inactive_count +
                            hostInfo64.free_count)
            
            let used = Float(hostInfo64.wire_count +
                           hostInfo64.active_count +
                           hostInfo64.inactive_count)
            
            return min(max(used / total, 0), 1)
        }
        
        return 0
    }
    
    func getGPUUsage(device: MTLDevice) -> Float {
        // Get GPU utilization through Metal's performance counters
        let gpuLoad = getGPULoadMetrics(device: device)
        return min(max(gpuLoad, 0), 1)
    }
    
    private func getGPULoadMetrics(device: MTLDevice) -> Float {
        var gpuUtilization: Float = 0.0
        
        let counterSet = MTLCounterSet.common
        if device.supportsCounterSampling(counterSet) {
            let sampleBuffer = device.makeCounterSampleBuffer(
                descriptor: MTLCounterSampleBufferDescriptor(),
                error: nil
            )
            
            if let sample = sampleBuffer?.sampleAtIndex(0) {
                // Extract GPU metrics from the sample
                // This is a simplified version - in practice, you'd analyze multiple metrics
                gpuUtilization = Float(sample.timestamp) / Float(device.maximumCommandBufferCount)
            }
        }
        
        return gpuUtilization
    }
    
    func getThermalState() -> ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    func getSystemLoad() -> SystemLoadMetrics {
        SystemLoadMetrics(
            cpuUsage: getCPUUsage(),
            memoryUsage: getMemoryUsage(),
            thermalState: getThermalState()
        )
    }
    
    deinit {
        if let prevCPUInfo = prevCPUInfo {
            prevCPUInfo.deallocate()
        }
    }
}

struct SystemLoadMetrics {
    let cpuUsage: Float
    let memoryUsage: Float
    let thermalState: ProcessInfo.ThermalState
    
    var isSystemStressed: Bool {
        cpuUsage > 0.85 || memoryUsage > 0.90 || thermalState == .serious
    }
    
    var recommendedOptimizations: [PerformanceOptimization] {
        var optimizations: [PerformanceOptimization] = []
        
        if cpuUsage > 0.85 {
            optimizations.append(.reduceScanningResolution)
            optimizations.append(.increaseFrameInterval)
        }
        
        if memoryUsage > 0.90 {
            optimizations.append(.clearPointBuffers)
            optimizations.append(.compressOlderFrames)
        }
        
        if thermalState == .serious {
            optimizations.append(.enterLowPowerMode)
        }
        
        return optimizations
    }
}
