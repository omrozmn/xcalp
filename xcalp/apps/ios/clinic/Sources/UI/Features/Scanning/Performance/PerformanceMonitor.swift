import Foundation
import os.log

/// Monitors performance of mesh processing and scanning operations
public final class PerformanceMonitor {
    public static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "performance")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.performance")
    private var measurements: [String: SignpostInterval] = [:]
    
    private init() {}
    
    @discardableResult
    public func startMeasuring(
        _ operation: String,
        signpostID: OSSignpostID? = nil,
        category: String? = nil
    ) -> OSSignpostID {
        let signpostID = signpostID ?? OSSignpostID(log: .default)
        let interval = SignpostInterval(
            id: signpostID,
            name: operation,
            category: category,
            startTime: CACurrentMediaTime()
        )
        
        queue.sync {
            measurements[operation] = interval
        }
        
        logger.debug("Started measuring \(operation)")
        return signpostID
    }
    
    public func endMeasuring(
        _ operation: String,
        signpostID: OSSignpostID,
        category: String? = nil
    ) {
        queue.sync {
            guard var interval = measurements[operation] else {
                logger.error("No measurement found for \(operation)")
                return
            }
            
            interval.endTime = CACurrentMediaTime()
            let duration = interval.duration
            
            logger.debug("""
                Finished \(operation):
                - Duration: \(duration)s
                - Category: \(category ?? "none")
                """)
            
            // Log to analytics
            AnalyticsService.shared.logPerformance(
                operation: operation,
                duration: duration,
                category: category
            )
            
            measurements.removeValue(forKey: operation)
        }
    }
    
    public func meetsPerformanceRequirements() -> Bool {
        // Check system conditions
        let thermalState = ProcessInfo.processInfo.thermalState
        let memoryPressure = os_proc_available_memory() < 500_000_000 // 500MB
        
        if thermalState == .critical || thermalState == .serious {
            logger.warning("Device in thermal state: \(thermalState)")
            return false
        }
        
        if memoryPressure {
            logger.warning("Device under memory pressure")
            return false
        }
        
        return true
    }
}

// MARK: - Supporting Types
private struct SignpostInterval {
    let id: OSSignpostID
    let name: String
    let category: String?
    let startTime: CFTimeInterval
    var endTime: CFTimeInterval?
    
    var duration: TimeInterval {
        guard let endTime = endTime else { return 0 }
        return endTime - startTime
    }
}
