import Foundation
import Metal

final class TestMonitor {
    private let healthChecker: SystemHealthChecker
    private let metricsCollector: MetricsCollector
    private let alertHandler: AlertHandler
    private var monitoredTests: [UUID: TestContext] = [:]
    private let monitorQueue = DispatchQueue(label: "com.xcalp.testmonitor")
    private var isMonitoring = false
    
    struct TestContext {
        let name: String
        let startTime: Date
        var metrics: TestMetrics
        var healthChecks: [HealthCheckResult]
        var alerts: [TestAlert]
        let expectedDuration: TimeInterval
    }
    
    struct TestMetrics {
        var cpuUsage: Double
        var memoryUsage: UInt64
        var gpuUsage: Double
        var ioOperations: UInt64
        var duration: TimeInterval
        var throughput: Double
        
        static var zero: TestMetrics {
            return TestMetrics(
                cpuUsage: 0,
                memoryUsage: 0,
                gpuUsage: 0,
                ioOperations: 0,
                duration: 0,
                throughput: 0
            )
        }
    }
    
    struct HealthCheckResult {
        let timestamp: Date
        let status: HealthStatus
        let component: SystemComponent
        let metrics: [String: Double]
        let message: String?
        
        enum HealthStatus {
            case healthy
            case degraded
            case unhealthy
            case critical
        }
        
        enum SystemComponent {
            case cpu
            case memory
            case gpu
            case io
            case network
        }
    }
    
    struct TestAlert {
        let timestamp: Date
        let severity: Severity
        let message: String
        let context: [String: String]
        
        enum Severity: Int {
            case info = 0
            case warning = 1
            case error = 2
            case critical = 3
        }
    }
    
    init(device: MTLDevice) {
        self.healthChecker = SystemHealthChecker(device: device)
        self.metricsCollector = MetricsCollector()
        self.alertHandler = AlertHandler()
        setupMonitoring()
    }
    
    func startMonitoring(
        testId: UUID,
        name: String,
        expectedDuration: TimeInterval
    ) {
        monitorQueue.async {
            self.monitoredTests[testId] = TestContext(
                name: name,
                startTime: Date(),
                metrics: .zero,
                healthChecks: [],
                alerts: [],
                expectedDuration: expectedDuration
            )
        }
    }
    
    func stopMonitoring(testId: UUID) -> TestContext? {
        return monitorQueue.sync {
            self.monitoredTests.removeValue(forKey: testId)
        }
    }
    
    func getTestStatus(testId: UUID) -> TestContext? {
        return monitorQueue.sync {
            self.monitoredTests[testId]
        }
    }
    
    private func setupMonitoring() {
        isMonitoring = true
        
        // Start periodic monitoring
        monitorQueue.async {
            while self.isMonitoring {
                self.performHealthCheck()
                self.collectMetrics()
                self.checkTestProgress()
                Thread.sleep(forTimeInterval: 1.0) // 1 second interval
            }
        }
    }
    
    private func performHealthCheck() {
        let results = healthChecker.checkSystemHealth()
        
        // Update test contexts with health check results
        for (testId, _) in monitoredTests {
            monitoredTests[testId]?.healthChecks.append(results)
            
            // Check for critical health issues
            if results.status == .critical {
                let alert = TestAlert(
                    timestamp: Date(),
                    severity: .critical,
                    message: "Critical system health issue detected: \(results.message ?? "")",
                    context: ["component": "\(results.component)"]
                )
                monitoredTests[testId]?.alerts.append(alert)
                alertHandler.handleAlert(alert)
            }
        }
    }
    
    private func collectMetrics() {
        for (testId, context) in monitoredTests {
            let metrics = metricsCollector.collectMetrics(for: testId)
            monitoredTests[testId]?.metrics = metrics
            
            // Check for metric thresholds
            checkMetricThresholds(metrics: metrics, context: context)
        }
    }
    
    private func checkTestProgress() {
        let now = Date()
        
        for (testId, context) in monitoredTests {
            let elapsed = now.timeIntervalSince(context.startTime)
            let progress = elapsed / context.expectedDuration
            
            // Check for slow tests
            if progress > 1.5 { // 50% longer than expected
                let alert = TestAlert(
                    timestamp: now,
                    severity: .warning,
                    message: "Test running longer than expected",
                    context: [
                        "test": context.name,
                        "expected": "\(context.expectedDuration)",
                        "elapsed": "\(elapsed)"
                    ]
                )
                monitoredTests[testId]?.alerts.append(alert)
                alertHandler.handleAlert(alert)
            }
        }
    }
    
    private func checkMetricThresholds(metrics: TestMetrics, context: TestContext) {
        // CPU usage threshold
        if metrics.cpuUsage > 90 {
            let alert = TestAlert(
                timestamp: Date(),
                severity: .warning,
                message: "High CPU usage detected",
                context: [
                    "test": context.name,
                    "cpu_usage": "\(metrics.cpuUsage)%"
                ]
            )
            alertHandler.handleAlert(alert)
        }
        
        // Memory usage threshold
        let memoryThresholdMB: UInt64 = 1024 * 1024 * 1024 // 1 GB
        if metrics.memoryUsage > memoryThresholdMB {
            let alert = TestAlert(
                timestamp: Date(),
                severity: .warning,
                message: "High memory usage detected",
                context: [
                    "test": context.name,
                    "memory_usage": "\(metrics.memoryUsage / 1024 / 1024) MB"
                ]
            )
            alertHandler.handleAlert(alert)
        }
    }
}

final class SystemHealthChecker {
    private let device: MTLDevice
    private let memoryThreshold: Double = 0.85 // 85%
    private let cpuThreshold: Double = 0.90 // 90%
    private let gpuThreshold: Double = 0.80 // 80%
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func checkSystemHealth() -> TestMonitor.HealthCheckResult {
        var status = TestMonitor.HealthCheckResult.HealthStatus.healthy
        var component = TestMonitor.HealthCheckResult.SystemComponent.cpu
        var message: String? = nil
        var metrics: [String: Double] = [:]
        
        // Check CPU
        let cpuUsage = getCurrentCPUUsage()
        metrics["cpu_usage"] = cpuUsage
        if cpuUsage > cpuThreshold {
            status = .critical
            component = .cpu
            message = "CPU usage exceeds threshold"
        }
        
        // Check Memory
        let memoryUsage = getCurrentMemoryUsage()
        metrics["memory_usage"] = memoryUsage
        if memoryUsage > memoryThreshold {
            status = .critical
            component = .memory
            message = "Memory usage exceeds threshold"
        }
        
        // Check GPU
        let gpuUsage = getCurrentGPUUsage()
        metrics["gpu_usage"] = gpuUsage
        if gpuUsage > gpuThreshold {
            status = .critical
            component = .gpu
            message = "GPU usage exceeds threshold"
        }
        
        return TestMonitor.HealthCheckResult(
            timestamp: Date(),
            status: status,
            component: component,
            metrics: metrics,
            message: message
        )
    }
    
    private func getCurrentCPUUsage() -> Double {
        var cpuInfo = processor_info_array_t?.init(nil)
        var numCpuInfo = mach_msg_type_number_t(0)
        var numCpus = 0
        
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )
        
        guard result == KERN_SUCCESS else { return 0 }
        
        var totalUsage: Double = 0
        for i in 0..<Int(numCpus) {
            let offset = i * Int(CPU_STATE_MAX)
            let user = Double(cpuInfo![offset + Int(CPU_STATE_USER)])
            let system = Double(cpuInfo![offset + Int(CPU_STATE_SYSTEM)])
            let idle = Double(cpuInfo![offset + Int(CPU_STATE_IDLE)])
            let total = user + system + idle
            totalUsage += (user + system) / total
        }
        
        return totalUsage / Double(numCpus)
    }
    
    private func getCurrentMemoryUsage() -> Double {
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
        
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return Double(info.resident_size) / Double(totalMemory)
    }
    
    private func getCurrentGPUUsage() -> Double {
        // This is a simplified approximation
        // Real GPU usage monitoring would require Metal Performance HUD
        return 0.0
    }
}

final class MetricsCollector {
    func collectMetrics(for testId: UUID) -> TestMonitor.TestMetrics {
        // Collect current metrics
        let cpuUsage = collectCPUMetrics()
        let memoryUsage = collectMemoryMetrics()
        let gpuUsage = collectGPUMetrics()
        let ioOps = collectIOMetrics()
        
        return TestMonitor.TestMetrics(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            gpuUsage: gpuUsage,
            ioOperations: ioOps,
            duration: 0,
            throughput: 0
        )
    }
    
    private func collectCPUMetrics() -> Double {
        // Implement CPU metrics collection
        return 0.0
    }
    
    private func collectMemoryMetrics() -> UInt64 {
        // Implement memory metrics collection
        return 0
    }
    
    private func collectGPUMetrics() -> Double {
        // Implement GPU metrics collection
        return 0.0
    }
    
    private func collectIOMetrics() -> UInt64 {
        // Implement I/O metrics collection
        return 0
    }
}

final class AlertHandler {
    private let alertQueue = DispatchQueue(label: "com.xcalp.alerthandler")
    private var alertObservers: [AlertObserver] = []
    
    func handleAlert(_ alert: TestMonitor.TestAlert) {
        alertQueue.async {
            // Notify all observers
            self.alertObservers.forEach { observer in
                observer.onAlert(alert)
            }
            
            // Log alert
            self.logAlert(alert)
            
            // Take action based on severity
            switch alert.severity {
            case .critical:
                self.handleCriticalAlert(alert)
            case .error:
                self.handleErrorAlert(alert)
            case .warning:
                self.handleWarningAlert(alert)
            case .info:
                self.handleInfoAlert(alert)
            }
        }
    }
    
    private func logAlert(_ alert: TestMonitor.TestAlert) {
        // Implement alert logging
    }
    
    private func handleCriticalAlert(_ alert: TestMonitor.TestAlert) {
        // Handle critical alerts
        NotificationCenter.default.post(
            name: .testCriticalAlert,
            object: nil,
            userInfo: ["alert": alert]
        )
    }
    
    private func handleErrorAlert(_ alert: TestMonitor.TestAlert) {
        // Handle error alerts
    }
    
    private func handleWarningAlert(_ alert: TestMonitor.TestAlert) {
        // Handle warning alerts
    }
    
    private func handleInfoAlert(_ alert: TestMonitor.TestAlert) {
        // Handle info alerts
    }
}

protocol AlertObserver {
    func onAlert(_ alert: TestMonitor.TestAlert)
}

extension Notification.Name {
    static let testCriticalAlert = Notification.Name("testCriticalAlert")
}