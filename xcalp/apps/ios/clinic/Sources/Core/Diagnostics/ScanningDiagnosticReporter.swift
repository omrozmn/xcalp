import Foundation
import Metal
import ARKit
import os.log
import CoreData

public class ScanningDiagnosticReporter {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningDiagnostics")
    private let errorHandler: ScanningErrorHandler
    private let performanceMonitor: PerformanceMonitor
    private let dataStore: ScanningDataStore
    
    init(
        errorHandler: ScanningErrorHandler,
        performanceMonitor: PerformanceMonitor,
        dataStore: ScanningDataStore
    ) {
        self.errorHandler = errorHandler
        self.performanceMonitor = performanceMonitor
        self.dataStore = dataStore
    }
    
    public func generateReport(
        sessionID: UUID,
        frame: ARFrame
    ) async -> DiagnosticSummary {
        let performance = performanceMonitor.reportResourceMetrics()
        let systemState = await collectSystemState()
        let errorHistory = errorHandler.getRecentErrors()
        
        let summary = DiagnosticSummary(
            sessionID: sessionID,
            timestamp: Date(),
            systemState: systemState,
            performance: performance,
            recentErrors: errorHistory
        )
        
        // Log diagnostic data
        await logDiagnostics(summary)
        
        // Store diagnostic data
        await storeDiagnostics(summary)
        
        return summary
    }
    
    public func reportQualityIssue(_ measurement: QualityMeasurement?) async {
        guard let measurement = measurement else { return }
        
        let issue = QualityIssue(
            timestamp: Date(),
            pointDensity: measurement.pointDensity,
            surfaceCompleteness: measurement.surfaceCompleteness,
            noiseLevel: measurement.noiseLevel,
            featurePreservation: measurement.featurePreservation
        )
        
        await dataStore.storeQualityIssue(issue)
        
        logger.warning("Quality issue detected: Point density: \(measurement.pointDensity), Surface completeness: \(measurement.surfaceCompleteness)")
    }
    
    public func reportLightingIssue() async {
        let issue = EnvironmentalIssue(
            type: .lighting,
            timestamp: Date(),
            severity: .warning
        )
        
        await dataStore.storeEnvironmentalIssue(issue)
        
        logger.warning("Lighting issue detected")
    }
    
    private func collectSystemState() async -> SystemState {
        let memoryInfo = ProcessInfo.processInfo.physicalMemory
        let thermalState = ProcessInfo.processInfo.thermalState
        let processorCount = ProcessInfo.processInfo.processorCount
        
        return SystemState(
            availableMemory: memoryInfo,
            thermalState: thermalState,
            processorCount: processorCount,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
    
    private func logDiagnostics(_ summary: DiagnosticSummary) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        if let diagnosticData = try? encoder.encode(summary),
           let diagnosticString = String(data: diagnosticData, encoding: .utf8) {
            logger.debug("Diagnostic summary: \(diagnosticString)")
        }
    }
    
    private func storeDiagnostics(_ summary: DiagnosticSummary) async {
        do {
            try await dataStore.storeDiagnosticSummary(summary)
        } catch {
            logger.error("Failed to store diagnostic data: \(error.localizedDescription)")
        }
    }
}

public struct DiagnosticSummary: Codable {
    public let sessionID: UUID
    public let timestamp: Date
    public let systemState: SystemState
    public let performance: ResourceMetrics
    public let recentErrors: [ScanningError]
}

public struct SystemState: Codable {
    public let availableMemory: UInt64
    public let thermalState: ProcessInfo.ThermalState
    public let processorCount: Int
    public let isLowPowerMode: Bool
}

public struct QualityIssue: Codable {
    public let timestamp: Date
    public let pointDensity: Float
    public let surfaceCompleteness: Double
    public let noiseLevel: Float
    public let featurePreservation: Float
}

public struct EnvironmentalIssue: Codable {
    public enum IssueType: String, Codable {
        case lighting
        case motion
        case surface
        case obstruction
    }
    
    public enum Severity: String, Codable {
        case warning
        case error
        case critical
    }
    
    public let type: IssueType
    public let timestamp: Date
    public let severity: Severity
}