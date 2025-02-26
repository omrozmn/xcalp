import Foundation
import Network
import SystemConfiguration
import CoreTelephony

public enum SystemStatus {
    case optimal
    case warning(String)
    case critical(String)
}

public class ScanningSystemMonitor {
    private let memoryThresholdWarning: Float = 0.8  // 80% memory usage
    private let memoryThresholdCritical: Float = 0.9 // 90% memory usage
    private let thermalStateMonitor = ProcessInfo.processInfo
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.xcalp.systemMonitor")
    
    private var onStatusChanged: ((SystemStatus) -> Void)?
    private var currentStatus: SystemStatus = .optimal
    
    public init(onStatusChanged: @escaping (SystemStatus) -> Void) {
        self.onStatusChanged = onStatusChanged
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkUpdate(path)
        }
        networkMonitor.start(queue: monitorQueue)
        
        // Setup periodic system checks
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkSystemStatus()
        }
    }
    
    private func checkSystemStatus() {
        monitorQueue.async { [weak self] in
            guard let self = self else { return }
            
            let memoryStatus = self.checkMemoryStatus()
            let thermalStatus = self.checkThermalState()
            
            // Determine overall system status
            let status = self.determineSystemStatus(
                memory: memoryStatus,
                thermal: thermalStatus
            )
            
            if status != self.currentStatus {
                self.currentStatus = status
                DispatchQueue.main.async {
                    self.onStatusChanged?(status)
                }
            }
        }
    }
    
    private func checkMemoryStatus() -> SystemStatus {
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
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Float(info.resident_size) / Float(ProcessInfo.processInfo.physicalMemory)
            
            if usedMemory > memoryThresholdCritical {
                return .critical("Critical memory usage: \(Int(usedMemory * 100))%")
            } else if usedMemory > memoryThresholdWarning {
                return .warning("High memory usage: \(Int(usedMemory * 100))%")
            }
        }
        
        return .optimal
    }
    
    private func checkThermalState() -> SystemStatus {
        switch thermalStateMonitor.thermalState {
        case .nominal:
            return .optimal
        case .fair:
            return .optimal
        case .serious:
            return .warning("Device temperature is high")
        case .critical:
            return .critical("Device temperature is critical")
        @unknown default:
            return .warning("Unknown thermal state")
        }
    }
    
    private func handleNetworkUpdate(_ path: NWPath) {
        switch path.status {
        case .satisfied:
            updateStatus(.optimal)
        case .unsatisfied:
            updateStatus(.warning("Network connectivity issues"))
        case .requiresConnection:
            updateStatus(.warning("Network connection required"))
        @unknown default:
            updateStatus(.warning("Unknown network status"))
        }
    }
    
    private func determineSystemStatus(
        memory: SystemStatus,
        thermal: SystemStatus
    ) -> SystemStatus {
        // Return the most severe status
        switch (memory, thermal) {
        case (.critical(let msg), _),
             (_, .critical(let msg)):
            return .critical(msg)
        case (.warning(let msg), _),
             (_, .warning(let msg)):
            return .warning(msg)
        default:
            return .optimal
        }
    }
    
    private func updateStatus(_ newStatus: SystemStatus) {
        if newStatus != currentStatus {
            currentStatus = newStatus
            DispatchQueue.main.async {
                self.onStatusChanged?(newStatus)
            }
        }
    }
    
    public func stop() {
        networkMonitor.cancel()
    }
}