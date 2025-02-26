import Foundation
import ARKit
import MetalKit
import os.log

final class ScanningDiagnostics {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningDiagnostics")
    private var performanceMetrics: [String: [Float]] = [:]
    private var diagnosticEvents: [DiagnosticEvent] = []
    private let maxHistorySize = 100
    
    struct DiagnosticReport {
        let timestamp: Date
        let sessionID: UUID
        let systemState: SystemState
        let performanceMetrics: PerformanceMetrics
        let qualityMetrics: QualityMetrics
        let recentEvents: [DiagnosticEvent]
        let recommendations: [Recommendation]
    }
    
    struct SystemState {
        let device: String
        let osVersion: String
        let arCapabilities: [String]
        let availableMemory: UInt64
        let thermalState: ProcessInfo.ThermalState
        let batteryLevel: Float
        let isLowPowerMode: Bool
    }
    
    struct PerformanceMetrics {
        let frameRate: Float
        let cpuUsage: Float
        let gpuUsage: Float
        let memoryUsage: Float
        let processingLatency: TimeInterval
        let trackingQuality: ARCamera.TrackingState
    }
    
    struct DiagnosticEvent {
        let timestamp: Date
        let type: EventType
        let message: String
        let metadata: [String: Any]
        
        enum EventType {
            case error
            case warning
            case info
            case recovery
            case optimization
        }
    }
    
    struct Recommendation {
        let priority: Priority
        let issue: String
        let solution: String
        let impact: String
        
        enum Priority {
            case critical
            case high
            case medium
            case low
        }
    }
    
    func generateDiagnosticReport(
        sessionID: UUID,
        frame: ARFrame?,
        qualityReport: MeshQualityAnalyzer.QualityReport?
    ) async -> DiagnosticReport {
        // Gather system state
        let systemState = await captureSystemState()
        
        // Collect performance metrics
        let performanceMetrics = await measurePerformanceMetrics(frame)
        
        // Generate recommendations
        let recommendations = analyzeAndGenerateRecommendations(
            systemState: systemState,
            performance: performanceMetrics,
            quality: qualityReport
        )
        
        return DiagnosticReport(
            timestamp: Date(),
            sessionID: sessionID,
            systemState: systemState,
            performanceMetrics: performanceMetrics,
            qualityMetrics: qualityReport?.toMetrics() ?? QualityMetrics(),
            recentEvents: Array(diagnosticEvents.suffix(20)),
            recommendations: recommendations
        )
    }
    
    func recordDiagnosticEvent(
        type: DiagnosticEvent.EventType,
        message: String,
        metadata: [String: Any] = [:]
    ) {
        let event = DiagnosticEvent(
            timestamp: Date(),
            type: type,
            message: message,
            metadata: metadata
        )
        
        diagnosticEvents.append(event)
        
        // Trim history if needed
        if diagnosticEvents.count > maxHistorySize {
            diagnosticEvents.removeFirst(diagnosticEvents.count - maxHistorySize)
        }
        
        // Log critical events
        if type == .error {
            logger.error("\(message, privacy: .public)")
        }
    }
    
    func updatePerformanceMetric(_ name: String, value: Float) {
        var values = performanceMetrics[name] ?? []
        values.append(value)
        
        // Keep last 60 values (1 minute at 1Hz)
        if values.count > 60 {
            values.removeFirst()
        }
        
        performanceMetrics[name] = values
    }
    
    private func captureSystemState() async -> SystemState {
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        
        // Get AR capabilities
        var capabilities: [String] = []
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            capabilities.append("lidar")
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
            capabilities.append("personSegmentation")
        }
        
        // Get available memory
        var pagesize: vm_size_t = 0
        var memoryInfo = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        
        host_page_size(mach_host_self(), &pagesize)
        _ = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        let availableMemory = UInt64(memoryInfo.free_count) * UInt64(pagesize)
        
        return SystemState(
            device: device.model,
            osVersion: device.systemVersion,
            arCapabilities: capabilities,
            availableMemory: availableMemory,
            thermalState: process.thermalState,
            batteryLevel: device.batteryLevel,
            isLowPowerMode: process.isLowPowerModeEnabled
        )
    }
    
    private func measurePerformanceMetrics(_ frame: ARFrame?) async -> PerformanceMetrics {
        // Calculate frame rate
        let frameRate = calculateAverageMetric("frameRate") ?? 0
        
        // Get CPU and GPU usage
        var cpuInfo = processor_info_array_t?.init(nil)
        var cpuCount = mach_msg_type_number_t(0)
        var processorCount: natural_t = 0
        host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &cpuInfo, &cpuCount)
        
        let cpuUsage = cpuInfo?.reduce(0.0) { sum, info in
            sum + Float(info) / Float(CPU_STATE_MAX)
        } ?? 0
        
        // Get tracking quality
        let trackingState = frame?.camera.trackingState ?? .notAvailable
        
        return PerformanceMetrics(
            frameRate: frameRate,
            cpuUsage: cpuUsage,
            gpuUsage: calculateAverageMetric("gpuUsage") ?? 0,
            memoryUsage: calculateAverageMetric("memoryUsage") ?? 0,
            processingLatency: calculateAverageMetric("processingLatency").map { TimeInterval($0) } ?? 0,
            trackingQuality: trackingState
        )
    }
    
    private func analyzeAndGenerateRecommendations(
        systemState: SystemState,
        performance: PerformanceMetrics,
        quality: MeshQualityAnalyzer.QualityReport?
    ) -> [Recommendation] {
        var recommendations: [Recommendation] = []
        
        // Check thermal state
        if systemState.thermalState == .serious || systemState.thermalState == .critical {
            recommendations.append(Recommendation(
                priority: .critical,
                issue: "Device overheating",
                solution: "Pause scanning and allow device to cool down",
                impact: "Prevents potential device shutdown and data loss"
            ))
        }
        
        // Check battery level
        if systemState.batteryLevel < 0.2 {
            recommendations.append(Recommendation(
                priority: .high,
                issue: "Low battery",
                solution: "Connect device to power source",
                impact: "Ensures uninterrupted scanning session"
            ))
        }
        
        // Check performance
        if performance.frameRate < 30 {
            recommendations.append(Recommendation(
                priority: .medium,
                issue: "Low frame rate",
                solution: "Reduce scanning quality settings or clear background apps",
                impact: "Improves scanning smoothness and quality"
            ))
        }
        
        // Check tracking quality
        if case .limited(let reason) = performance.trackingQuality {
            let (issue, solution) = diagnoseLimitedTracking(reason)
            recommendations.append(Recommendation(
                priority: .high,
                issue: issue,
                solution: solution,
                impact: "Ensures accurate scan alignment and reconstruction"
            ))
        }
        
        // Check quality metrics
        if let quality = quality {
            if quality.surfaceCompleteness < 0.8 {
                recommendations.append(Recommendation(
                    priority: .medium,
                    issue: "Incomplete surface coverage",
                    solution: "Scan from multiple angles and ensure full coverage",
                    impact: "Improves model completeness and accuracy"
                ))
            }
            
            if quality.noiseLevel > 0.3 {
                recommendations.append(Recommendation(
                    priority: .medium,
                    issue: "High noise levels",
                    solution: "Hold device more steady and ensure good lighting",
                    impact: "Reduces artifacts and improves detail quality"
                ))
            }
        }
        
        return recommendations
    }
    
    private func calculateAverageMetric(_ name: String) -> Float? {
        guard let values = performanceMetrics[name], !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Float(values.count)
    }
    
    private func diagnoseLimitedTracking(_ reason: ARCamera.TrackingState.Reason) -> (String, String) {
        switch reason {
        case .initializing:
            return (
                "Tracking system initializing",
                "Hold device still and wait for initialization to complete"
            )
        case .excessiveMotion:
            return (
                "Excessive device motion",
                "Move the device more slowly and steadily"
            )
        case .insufficientFeatures:
            return (
                "Insufficient visual features",
                "Ensure adequate lighting and scan areas with more visual details"
            )
        case .relocalizing:
            return (
                "Lost tracking reference",
                "Return to a previously scanned area"
            )
        @unknown default:
            return (
                "Unknown tracking issue",
                "Try resetting the scanning session"
            )
        }
    }
    
    func exportDiagnosticData() throws -> Data {
        let report = DiagnosticExport(
            events: diagnosticEvents,
            performanceHistory: performanceMetrics
        )
        return try JSONEncoder().encode(report)
    }
}

private struct DiagnosticExport: Codable {
    let events: [DiagnosticEvent]
    let performanceHistory: [String: [Float]]
}

extension DiagnosticEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case message
        case metadata
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(message, forKey: .message)
        try container.encode(metadata.mapValues { String(describing: $0) }, forKey: .metadata)
    }
}

extension DiagnosticEvent.EventType: Codable {
    var rawValue: String {
        switch self {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        case .recovery: return "recovery"
        case .optimization: return "optimization"
        }
    }
}

extension MeshQualityAnalyzer.QualityReport {
    func toMetrics() -> QualityMetrics {
        QualityMetrics(
            pointDensity: pointDensity,
            surfaceCompleteness: surfaceCompleteness,
            noiseLevel: noiseLevel,
            featurePreservation: featurePreservation
        )
    }
}