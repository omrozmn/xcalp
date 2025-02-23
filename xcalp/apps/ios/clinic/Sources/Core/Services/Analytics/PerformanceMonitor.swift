import Foundation
import MetalKit
import os.signpost
import os.log
#if canImport(QuartzCore)
import QuartzCore
#endif

/// Service for monitoring app performance metrics
@MainActor
public final class PerformanceMonitor: ObservableObject {
    public static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.performance", qos: .utility)
    private let lock = NSLock()
    
    // Performance thresholds from blueprint
    private let maxMemoryUsage: UInt64 = 200 * 1024 * 1024  // 200MB
    private let minFrameRate: Double = 30.0
    private let maxProcessingTime: TimeInterval = 5.0
    private let thermalThreshold = ProcessInfo.ThermalState.serious
    
    private var metrics: [String: [TimeInterval]] = [:]
    private var signposts: [String: OSSignpostID] = [:]
    private var metalCommandQueue: MTLCommandQueue?
    private var thermalStateObserver: NSObjectProtocol?
    
    private let osLog = OSLog(subsystem: "com.xcalp.clinic", category: "Performance")
    private let signposter = OSSignposter(subsystem: "com.xcalp.clinic", category: "Performance")
    
    @Published private(set) var memoryUsage: UInt64 = 0
    @Published private(set) var frameRate: Double = 0
    @Published private(set) var gpuUtilization: Double = 0
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var isPerformanceLimited: Bool = false
    
    private init() {
        setupMetalTracking()
        setupThermalMonitoring()
        startMonitoring()
    }
    
    private func setupMetalTracking() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Failed to create Metal device")
            return
        }
        metalCommandQueue = device.makeCommandQueue()
    }
    
    private func setupThermalMonitoring() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
        thermalState = ProcessInfo.processInfo.thermalState
    }
    
    private func handleThermalStateChange() {
        let newState = ProcessInfo.processInfo.thermalState
        thermalState = newState
        
        if newState.rawValue >= thermalThreshold.rawValue {
            isPerformanceLimited = true
            logger.warning("Performance limited due to thermal state: \(newState)")
            Task { @MainActor in
                await reduceResourceUsage()
            }
        } else {
            isPerformanceLimited = false
        }
    }
    
    private func reduceResourceUsage() async {
        // Clear image caches
        URLCache.shared.removeAllCachedResponses()
        
        // Release unused Metal resources
        metalCommandQueue?.insertDebugCaptureBoundary()
        
        // Request resource cleanup
        await ResourceManager.shared.cleanupUnusedResources()
        
        // Force garbage collection if available
        #if DEBUG
        autoreleasepool {
            _ = malloc_size(malloc(1))  // Force memory pressure
        }
        #endif
    }
    
    public func startMeasuring(
        _ name: String,
        category: String
    ) -> OSSignpostID {
        lock.lock()
        defer { lock.unlock() }
        
        let signpostID = signposter.makeSignpostID()
        signposts[name] = signpostID
        
        signposter.emitBegin(signpostID, name)
        logger.debug("Started measuring \(name)")
        
        return signpostID
    }
    
    public func endMeasuring(
        _ name: String,
        signpostID: OSSignpostID,
        category: String,
        error: Error? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        signposter.emitEnd(signpostID, name)
        
        if let error = error {
            logger.error("Measurement \(name) failed: \(error.localizedDescription)")
            AnalyticsService.shared.logError(error, severity: .error, context: [
                "measurement": name,
                "category": category
            ])
        } else {
            if let interval = getSignpostInterval(for: name, id: signpostID) {
                queue.async {
                    self.updateMetrics(name: name, duration: interval)
                }
            }
        }
        
        signposts.removeValue(forKey: name)
    }
    
    private func getSignpostInterval(for name: String, id: OSSignpostID) -> TimeInterval? {
        // Get interval from signpost if available
        return 0.5 // Placeholder - actual implementation would use OSSignpostIntervalState
    }
    
    private func updateMetrics(name: String, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        
        var measurements = metrics[name] ?? []
        measurements.append(duration)
        
        // Keep only last 100 measurements
        if measurements.count > 100 {
            measurements.removeFirst(measurements.count - 100)
        }
        
        metrics[name] = measurements
        
        // Log if performance threshold exceeded
        let average = measurements.reduce(0, +) / Double(measurements.count)
        if average > maxProcessingTime {
            logger.warning("\(name) average duration (\(average)s) exceeds threshold (\(maxProcessingTime)s)")
        }
        
        logMetrics(name: name, duration: average)
    }
    
    private func startMonitoring() {
        // Monitor memory usage
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
            self?.updateFrameRate()
            self?.updateGPUUtilization()
        }
        
        // Initial update
        updateMemoryUsage()
    }
    
    private func updateMemoryUsage() {
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
            let oldUsage = memoryUsage
            memoryUsage = info.resident_size
            
            // Check for significant memory increases
            if memoryUsage > oldUsage && (Double(memoryUsage - oldUsage) / Double(oldUsage)) > 0.2 {
                logger.warning("Memory usage increased by >20%: \(ByteCountFormatter.string(fromByteCount: Int64(memoryUsage - oldUsage), countStyle: .memory))")
            }
            
            // Check against threshold
            if memoryUsage > maxMemoryUsage {
                logger.warning("Memory usage exceeds limit: \(ByteCountFormatter.string(fromByteCount: Int64(memoryUsage), countStyle: .memory))")
                Task { @MainActor in
                    await reduceResourceUsage()
                }
            }
        }
    }
    
    private func updateFrameRate() {
        // Use CADisplayLink for accurate frame rate
        #if os(iOS)
        if let displayLink = displayLink {
            frameRate = 1.0 / displayLink.targetTimestamp
            
            if frameRate < minFrameRate {
                logger.warning("Frame rate below requirement: \(Int(frameRate)) FPS")
                isPerformanceLimited = true
            } else {
                isPerformanceLimited = false
            }
        }
        #endif
    }
    
    private func updateGPUUtilization() {
        guard let commandQueue = metalCommandQueue else { return }
        
        // Get GPU counters using Metal Performance Shaders
        // This is a placeholder - actual implementation would use MTLCounters
        let utilization = 0.0
        
        gpuUtilization = utilization
        
        if utilization > 0.8 { // 80% threshold
            logger.warning("High GPU utilization: \(Int(utilization * 100))%")
            isPerformanceLimited = true
        }
    }
    
    public func meetsPerformanceRequirements() -> Bool {
        let meetsMemoryRequirement = memoryUsage < maxMemoryUsage
        let meetsFrameRateRequirement = frameRate >= minFrameRate
        let meetsThermalRequirement = thermalState.rawValue < thermalThreshold.rawValue
        
        return meetsMemoryRequirement && meetsFrameRateRequirement && meetsThermalRequirement
    }
    
    private func logMetrics(name: String, duration: TimeInterval) {
        AnalyticsService.shared.logPerformance(
            name: name,
            duration: duration,
            memoryUsage: Int64(currentMemoryUsage())
        )
    }
    
    public func currentMemoryUsage() -> UInt64 {
        memoryUsage
    }
    
    public func currentFrameRate() -> Double {
        frameRate
    }
    
    deinit {
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    #if os(iOS)
    private var displayLink: CADisplayLink?
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func displayLinkFired() {
        // Frame timing handled in updateFrameRate()
    }
    #endif
}

// MARK: - Array Extension
private extension Array where Element == TimeInterval {
    var average: TimeInterval {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / TimeInterval(count)
    }
}