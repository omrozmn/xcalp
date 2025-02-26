import Foundation
import Metal
import ARKit
import CoreML
import os.log

/// Central coordinator managing interactions between scanning subsystems
public final class ScanningSystemCoordinator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningSystemCoordinator")
    
    // Core processing systems
    private let meshProcessor: MeshProcessingCoordinator
    private let qualityCoordinator: ScanningQualityCoordinator
    private let performanceMonitor: PerformanceMonitor
    private let diagnosticReporter: ScanningDiagnosticReporter
    private let errorHandler: ScanningErrorHandler
    
    // Analysis systems
    private let lightingAnalyzer: LightingAnalyzer
    private let qualityAnalyzer: MeshQualityAnalyzer
    private let adaptiveQuality: AdaptiveQualityManager
    
    // Configuration
    private let config = AppConfiguration.Performance.Scanning.self
    
    // State management
    private var currentMode: ScanningMode = .lidar
    private var currentSession: UUID?
    private var isProcessingFrame = false
    private var qualityHistory: [QualityMeasurement] = []
    private var fallbackAttempts = 0
    private let maxFallbackAttempts = 3
    
    public init(device: MTLDevice) throws {
        // Initialize subsystems
        self.meshProcessor = try MeshProcessingCoordinator(device: device)
        self.qualityCoordinator = try ScanningQualityCoordinator(device: device)
        self.performanceMonitor = .shared
        self.lightingAnalyzer = try LightingAnalyzer()
        self.qualityAnalyzer = try MeshQualityAnalyzer(device: device)
        self.errorHandler = ScanningErrorHandler()
        self.adaptiveQuality = .shared
        
        // Initialize diagnostic reporter
        self.diagnosticReporter = ScanningDiagnosticReporter(
            errorHandler: errorHandler,
            performanceMonitor: performanceMonitor,
            dataStore: try ScanningDataStore.shared
        )
        
        setupPerformanceMonitoring()
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor.observe { [weak self] metrics in
            guard let self = self else { return }
            Task {
                await self.adaptiveQuality.updateQualitySettings(
                    performance: metrics,
                    environment: await self.getCurrentEnvironmentMetrics()
                )
            }
        }
    }
    
    public func startNewSession(
        mode: ScanningMode,
        configuration: ScanningConfiguration
    ) async throws {
        currentSession = UUID()
        currentMode = mode
        fallbackAttempts = 0
        
        // Create session record
        let session = try await ScanningDataStore.shared.createScanningSession(
            mode: mode,
            configuration: configuration.toDictionary(),
            timestamp: Date()
        )
        
        // Initialize subsystems
        try await initializeSubsystems(for: mode, configuration: configuration)
        
        logger.info("Started scanning session: \(session.id?.uuidString ?? "unknown")")
    }
    
    public func processFrame(_ frame: ARFrame) async throws -> FrameProcessingResult {
        guard let sessionID = currentSession else {
            throw ScanningError.invalidSession
        }
        
        guard !isProcessingFrame else {
            throw ScanningError.processingInProgress
        }
        
        isProcessingFrame = true
        defer { isProcessingFrame = false }
        
        do {
            // Start performance tracking
            let signpostID = performanceMonitor.startMeasuring("frameProcessing", category: "scanning")
            defer { performanceMonitor.endMeasuring("frameProcessing", signpostID: signpostID, category: "scanning") }
            
            // Parallel analysis
            async let qualityAssessment = qualityCoordinator.processFrame(frame)
            async let lightingAnalysis = lightingAnalyzer.analyzeLighting(frame)
            async let diagnosticSummary = diagnosticReporter.generateReport(
                sessionID: sessionID,
                frame: frame
            )
            
            // Wait for parallel analysis
            let (quality, lighting, diagnostics) = try await (
                qualityAssessment,
                lightingAnalysis,
                diagnosticSummary
            )
            
            // Update quality history
            updateQualityHistory(quality)
            
            // Check for quality issues
            try await handleQualityIssues(quality, lighting: lighting)
            
            // Process mesh if quality is acceptable
            let processedMesh = try await processMeshIfQualityAcceptable(
                frame: frame,
                quality: quality
            )
            
            return FrameProcessingResult(
                mesh: processedMesh,
                quality: quality,
                lighting: lighting,
                diagnostics: diagnostics
            )
        } catch {
            await handleProcessingError(error)
            throw error
        }
    }
    
    private func initializeSubsystems(
        for mode: ScanningMode,
        configuration: ScanningConfiguration
    ) async throws {
        try await meshProcessor.configure(for: mode, with: configuration)
        try await qualityCoordinator.initialize(mode: mode)
        performanceMonitor.updatePhase(.scanning)
    }
    
    private func updateQualityHistory(_ quality: QualityAssessment) {
        let measurement = QualityMeasurement(
            timestamp: Date(),
            pointDensity: quality.pointDensity,
            surfaceCompleteness: quality.surfaceCompleteness,
            noiseLevel: quality.noiseLevel,
            featurePreservation: quality.featurePreservation
        )
        
        qualityHistory.append(measurement)
        
        // Keep only recent history
        qualityHistory = qualityHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -10 // Last 10 seconds
        }
    }
    
    private func handleQualityIssues(
        _ quality: QualityAssessment,
        lighting: LightingAnalysis
    ) async throws {
        // Check against thresholds
        if quality.pointDensity < config.minPointDensity ||
           quality.surfaceCompleteness < config.minSurfaceCompleteness ||
           quality.noiseLevel > config.maxNoiseLevel ||
           quality.featurePreservation < config.minFeaturePreservation {
            
            // Try fallback if available
            if fallbackAttempts < maxFallbackAttempts {
                fallbackAttempts += 1
                try await switchToFallbackMode()
            } else {
                throw ScanningError.qualityBelowThreshold
            }
        }
        
        // Check lighting conditions
        if lighting.intensity < config.minLightIntensity {
            throw ScanningError.insufficientLighting
        }
    }
    
    private func switchToFallbackMode() async throws {
        switch currentMode {
        case .lidar:
            currentMode = .photogrammetry
        case .photogrammetry:
            currentMode = .hybrid
        case .hybrid:
            throw ScanningError.noFallbackAvailable
        }
        
        try await initializeSubsystems(
            for: currentMode,
            configuration: ScanningConfiguration()
        )
    }
    
    private func processMeshIfQualityAcceptable(
        frame: ARFrame,
        quality: QualityAssessment
    ) async throws -> ProcessedMesh {
        guard quality.isAcceptable else {
            throw ScanningError.qualityBelowThreshold
        }
        
        return try await meshProcessor.processMesh(
            frame: frame,
            quality: quality
        )
    }
    
    private func getCurrentEnvironmentMetrics() async -> EnvironmentMetrics {
        // Get current environment conditions for adaptive quality
        return EnvironmentMetrics(
            lightingLevel: qualityHistory.last?.lightingScore ?? 1.0,
            motionStability: qualityHistory.last?.motionScore ?? 1.0,
            surfaceComplexity: qualityHistory.last?.complexityScore ?? 0.5
        )
    }
    
    private func handleProcessingError(_ error: Error) async {
        logger.error("Processing error: \(error.localizedDescription)")
        errorHandler.handle(error, severity: .high)
        
        if let scanningError = error as? ScanningError {
            switch scanningError {
            case .qualityBelowThreshold:
                await diagnosticReporter.reportQualityIssue(qualityHistory.last)
            case .insufficientLighting:
                await diagnosticReporter.reportLightingIssue()
            default:
                break
            }
        }
    }
}

// MARK: - Supporting Types

struct ScanningConfiguration {
    let qualityPreset: MeshQualityConfig.QualityPreset
    let optimizationParameters: MeshOptimizer.OptimizationParameters
    let validationStages: Set<MeshValidationSystem.ValidationStage>
    let reconstructionOptions: MeshReconstructor.ReconstructionOptions
    let qualityThresholds: MeshQualityConfig.QualityThresholds
    
    func toDictionary() -> [String: Any] {
        // Convert configuration to dictionary for storage
        return [:]  // Implementation needed
    }
}

struct FrameProcessingResult {
    let mesh: ProcessedMesh
    let quality: QualityAssessment
    let lighting: LightingAnalysis
    let diagnostics: DiagnosticSummary
}

enum ScanningError: Error {
    case invalidSession
    case processingInProgress
    case deviceNotSupported
    case invalidFrameData
    case qualityBelowThreshold
    case unrecoverableError
    case insufficientLighting
    case noFallbackAvailable
}