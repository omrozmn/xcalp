import Foundation
import Metal
import MetalPerformanceShaders
import QuartzCore

final class MeshProcessingProfiler {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var profiles: [String: [ProfileMetrics]] = [:]
    private var activeProfiles: [String: ProfileSession] = [:]
    
    struct ProfileMetrics {
        let cpuTime: CFTimeInterval
        let gpuTime: CFTimeInterval
        let memoryPeak: UInt64
        let gpuMemoryPeak: UInt64
        let timestamp: Date
        let metadata: [String: Any]
        
        var totalTime: CFTimeInterval {
            return max(cpuTime, gpuTime)
        }
    }
    
    struct ProfileSession {
        let startTime: CFTimeInterval
        let startMemory: UInt64
        let counterSet: MTLCounterSet?
        let sampleBuffer: MTLCounterSampleBuffer?
    }
    
    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw ProfilerError.initializationFailed
        }
        self.commandQueue = queue
    }
    
    func beginProfiling(_ identifier: String, metadata: [String: Any] = [:]) throws {
        guard activeProfiles[identifier] == nil else {
            throw ProfilerError.sessionAlreadyActive
        }
        
        let startTime = CACurrentMediaTime()
        let startMemory = getMemoryUsage()
        
        // Setup GPU counters if available
        let counterSet = try? setupGPUCounters()
        let sampleBuffer = try? createCounterSampleBuffer()
        
        if let buffer = sampleBuffer {
            commandQueue.sampleTimestamps(&buffer.gpuStartTime, &buffer.gpuEndTime)
        }
        
        activeProfiles[identifier] = ProfileSession(
            startTime: startTime,
            startMemory: startMemory,
            counterSet: counterSet,
            sampleBuffer: sampleBuffer
        )
    }
    
    func endProfiling(_ identifier: String) throws -> ProfileMetrics {
        guard let session = activeProfiles.removeValue(forKey: identifier) else {
            throw ProfilerError.noActiveSession
        }
        
        let endTime = CACurrentMediaTime()
        let endMemory = getMemoryUsage()
        
        var gpuTime: CFTimeInterval = 0
        var gpuMemoryPeak: UInt64 = 0
        
        if let buffer = session.sampleBuffer {
            commandQueue.sampleTimestamps(&buffer.gpuStartTime, &buffer.gpuEndTime)
            gpuTime = buffer.gpuEndTime - buffer.gpuStartTime
            gpuMemoryPeak = try getGPUMemoryPeak(buffer)
        }
        
        let metrics = ProfileMetrics(
            cpuTime: endTime - session.startTime,
            gpuTime: gpuTime,
            memoryPeak: max(endMemory, session.startMemory),
            gpuMemoryPeak: gpuMemoryPeak,
            timestamp: Date(),
            metadata: [:]
        )
        
        profiles[identifier, default: []].append(metrics)
        return metrics
    }
    
    func generateReport() -> ProfileReport {
        var report = ProfileReport()
        
        for (identifier, metrics) in profiles {
            let averageCPUTime = metrics.map { $0.cpuTime }.reduce(0, +) / Double(metrics.count)
            let averageGPUTime = metrics.map { $0.gpuTime }.reduce(0, +) / Double(metrics.count)
            let maxMemory = metrics.map { $0.memoryPeak }.max() ?? 0
            let maxGPUMemory = metrics.map { $0.gpuMemoryPeak }.max() ?? 0
            
            report.addSection(
                identifier: identifier,
                metrics: ProfileSummary(
                    averageCPUTime: averageCPUTime,
                    averageGPUTime: averageGPUTime,
                    peakMemory: maxMemory,
                    peakGPUMemory: maxGPUMemory,
                    sampleCount: metrics.count
                )
            )
        }
        
        return report
    }
    
    private func setupGPUCounters() throws -> MTLCounterSet {
        guard let counterSet = device.counterSets.first(where: { $0.name == "Statistics" }) else {
            throw ProfilerError.counterSetUnavailable
        }
        return counterSet
    }
    
    private func createCounterSampleBuffer() throws -> MTLCounterSampleBuffer {
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.sampleCount = 1
        descriptor.storageMode = .shared
        
        return try device.makeCounterSampleBuffer(descriptor: descriptor)
    }
    
    private func getGPUMemoryPeak(_ buffer: MTLCounterSampleBuffer) throws -> UInt64 {
        // Implementation would depend on specific GPU counter support
        return 0
    }
    
    private func getMemoryUsage() -> UInt64 {
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
        
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

struct ProfileReport {
    private var sections: [String: ProfileSummary] = [:]
    
    mutating func addSection(identifier: String, metrics: ProfileSummary) {
        sections[identifier] = metrics
    }
    
    var summary: String {
        return sections.map { id, metrics in
            """
            \(id):
                CPU Time: \(String(format: "%.3f", metrics.averageCPUTime))s
                GPU Time: \(String(format: "%.3f", metrics.averageGPUTime))s
                Memory: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.peakMemory), countStyle: .memory))
                GPU Memory: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.peakGPUMemory), countStyle: .memory))
                Samples: \(metrics.sampleCount)
            """
        }.joined(separator: "\n\n")
    }
    
    func getMetrics(for identifier: String) -> ProfileSummary? {
        return sections[identifier]
    }
}

struct ProfileSummary {
    let averageCPUTime: CFTimeInterval
    let averageGPUTime: CFTimeInterval
    let peakMemory: UInt64
    let peakGPUMemory: UInt64
    let sampleCount: Int
}

enum ProfilerError: Error {
    case initializationFailed
    case sessionAlreadyActive
    case noActiveSession
    case counterSetUnavailable
}