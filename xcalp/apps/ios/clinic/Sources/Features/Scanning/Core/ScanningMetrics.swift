import Foundation
import ARKit

public struct ScanningMetrics {
    let frameRate: Double
    let processingTime: TimeInterval
    let pointCount: Int
    let memoryUsage: UInt64
    let batteryLevel: Float
    let deviceTemperature: Float
    let isPerformanceAcceptable: Bool
    
    var description: String {
        """
        Frame Rate: \(String(format: "%.1f", frameRate)) FPS
        Processing Time: \(String(format: "%.2f", processingTime * 1000))ms
        Points: \(pointCount)
        Memory: \(formatMemory(memoryUsage))
        Battery: \(Int(batteryLevel * 100))%
        Temperature: \(String(format: "%.1f", deviceTemperature))°C
        """
    }
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", megabytes)
    }
}

public class ScanningMetricsCollector {
    private var frameTimeHistory: [TimeInterval] = []
    private let maxHistorySize = 60
    private var lastFrameTime: TimeInterval = 0
    
    public func recordFrame() {
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameTime = currentTime - lastFrameTime
            frameTimeHistory.append(frameTime)
            
            if frameTimeHistory.count > maxHistorySize {
                frameTimeHistory.removeFirst()
            }
        }
        lastFrameTime = currentTime
    }
    
    public func getCurrentMetrics(
        processingTime: TimeInterval,
        pointCount: Int
    ) -> ScanningMetrics {
        let frameRate = calculateFrameRate()
        let memoryUsage = getMemoryUsage()
        let batteryLevel = getBatteryLevel()
        let temperature = getDeviceTemperature()
        
        let isAcceptable = frameRate > 25 &&
                          processingTime < 0.033 &&
                          memoryUsage < 500_000_000 &&
                          temperature < 35
        
        return ScanningMetrics(
            frameRate: frameRate,
            processingTime: processingTime,
            pointCount: pointCount,
            memoryUsage: memoryUsage,
            batteryLevel: batteryLevel,
            deviceTemperature: temperature,
            isPerformanceAcceptable: isAcceptable
        )
    }
    
    private func calculateFrameRate() -> Double {
        guard !frameTimeHistory.isEmpty else { return 0 }
        let averageFrameTime = frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
        return 1.0 / averageFrameTime
    }
    
    private func getMemoryUsage() -> UInt64 {
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
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func getBatteryLevel() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }
    
    private func getDeviceTemperature() -> Float {
        // This is a placeholder as iOS doesn't provide direct access to temperature
        // In a real implementation, we might use thermal state as a proxy
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return 25.0
        case .fair:
            return 30.0
        case .serious:
            return 35.0
        case .critical:
            return 40.0
        @unknown default:
            return 25.0
        }
    }
    
    func reset() {
        frameTimeHistory.removeAll()
        lastFrameTime = 0
    }
}