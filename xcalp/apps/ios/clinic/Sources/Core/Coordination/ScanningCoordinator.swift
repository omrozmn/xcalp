import Foundation
import ARKit
import Combine
import os.log

final class ScanningCoordinator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningCoordinator")
    private let qualityAnalyzer: MeshQualityAnalyzer
    private let guidanceSystem: ScanningGuidanceSystem
    private let errorRecovery: ScanningErrorRecovery
    private var cancellables = Set<AnyCancellable>()
    
    // Component states
    private var currentMode: ScanningMode = .lidar
    private var isProcessing = false
    private var qualityHistory: [QualityReport] = []
    
    // Quality thresholds from config
    private let qualityConfig = MeshQualityConfig.self
    
    init() throws {
        self.qualityAnalyzer = try MeshQualityAnalyzer()
        self.guidanceSystem = ScanningGuidanceSystem()
        self.errorRecovery = ScanningErrorRecovery()
        
        setupQualityMonitoring()
    }
    
    func startScanning() async throws {
        logger.info("Starting scanning session")
        
        // Initialize components
        guidanceSystem.startGuidance()
        
        // Start with optimal scanning mode
        currentMode = determineOptimalScanningMode()
        try await configureScanningSession()
    }
    
    func processFrame(_ frame: ARFrame) async throws {
        guard !isProcessing else { return }
        isProcessing = true
        
        defer { isProcessing = false }
        
        do {
            // Update guidance based on frame
            let guidanceUpdate = guidanceSystem.updateGuidance(frame: frame)
            
            // Process frame based on current mode
            switch currentMode {
            case .lidar:
                try await processLiDARFrame(frame)
            case .photogrammetry:
                try await processPhotogrammetryFrame(frame)
            case .hybrid:
                try await processHybridFrame(frame)
            }
            
            // Update UI with guidance
            await updateUI(with: guidanceUpdate)
            
        } catch {
            try await handleProcessingError(error)
        }
    }
    
    private func configureScanningSession() async throws {
        let config = ARWorldTrackingConfiguration()
        
        switch currentMode {
        case .lidar:
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
                throw ScanningError.deviceNotSupported
            }
            config.sceneReconstruction = .mesh
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            
        case .photogrammetry:
            config.frameSemantics = [.personSegmentation]
            
        case .hybrid:
            config.sceneReconstruction = .mesh
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth, .personSegmentation]
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("ConfigureARSession"),
            object: nil,
            userInfo: ["configuration": config]
        )
    }
    
    private func processLiDARFrame(_ frame: ARFrame) async throws {
        guard let meshAnchor = frame.anchors.first(where: { $0 is ARMeshAnchor }) as? ARMeshAnchor else {
            return
        }
        
        let meshData = MeshData(
            vertices: Array(meshAnchor.geometry.vertices),
            indices: Array(meshAnchor.geometry.faces),
            normals: Array(meshAnchor.geometry.normals),
            confidence: []
        )
        
        let qualityReport = try await qualityAnalyzer.analyzeMesh(meshData)
        updateQualityHistory(with: qualityReport)
        
        if !qualityReport.isAcceptable {
            throw ScanningError.qualityBelowThreshold
        }
    }
    
    private func processPhotogrammetryFrame(_ frame: ARFrame) async throws {
        // Process photogrammetry data
        let photoData = try await extractPhotogrammetryData(frame)
        let meshData = try await reconstructMeshFromPhotogrammetry(photoData)
        
        let qualityReport = try await qualityAnalyzer.analyzeMesh(meshData)
        updateQualityHistory(with: qualityReport)
        
        if !qualityReport.isAcceptable {
            throw ScanningError.qualityBelowThreshold
        }
    }
    
    private func processHybridFrame(_ frame: ARFrame) async throws {
        // Process both LiDAR and photogrammetry data
        async let lidarMesh = extractLiDARMesh(frame)
        async let photoMesh = extractPhotogrammetryMesh(frame)
        
        // Fuse the data
        let fusedMesh = try await fuseMeshData(
            lidarMesh: lidarMesh,
            photoMesh: photoMesh
        )
        
        let qualityReport = try await qualityAnalyzer.analyzeMesh(fusedMesh)
        updateQualityHistory(with: qualityReport)
        
        if !qualityReport.isAcceptable {
            throw ScanningError.qualityBelowThreshold
        }
    }
    
    private func handleProcessingError(_ error: Error) async throws {
        logger.error("Processing error: \(error.localizedDescription)")
        
        if await errorRecovery.attemptRecovery(from: error) {
            logger.info("Successfully recovered from error")
            return
        }
        
        // If recovery failed, try switching modes
        switch currentMode {
        case .lidar:
            currentMode = .hybrid
            try await configureScanningSession()
        case .hybrid:
            currentMode = .photogrammetry
            try await configureScanningSession()
        case .photogrammetry:
            throw ScanningError.unrecoverableError
        }
    }
    
    private func determineOptimalScanningMode() -> ScanningMode {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return .lidar
        } else {
            return .photogrammetry
        }
    }
    
    private func updateQualityHistory(with report: QualityReport) {
        qualityHistory.append(report)
        
        // Keep last 30 reports
        if qualityHistory.count > 30 {
            qualityHistory.removeFirst()
        }
        
        analyzeQualityTrend()
    }
    
    private func analyzeQualityTrend() {
        guard qualityHistory.count >= 5 else { return }
        
        let recentReports = qualityHistory.suffix(5)
        let averageQuality = recentReports.map { $0.surfaceCompleteness }.reduce(0, +) / Float(recentReports.count)
        
        if averageQuality < qualityConfig.minimumSurfaceCompleteness {
            NotificationCenter.default.post(
                name: Notification.Name("QualityWarning"),
                object: nil,
                userInfo: ["quality": averageQuality]
            )
        }
    }
    
    private func setupQualityMonitoring() {
        NotificationCenter.default.publisher(for: Notification.Name("QualityWarning"))
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let quality = notification.userInfo?["quality"] as? Float {
                    self.handleQualityWarning(quality)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleQualityWarning(_ quality: Float) {
        Task {
            do {
                // Attempt to improve quality
                let adjustedParams = calculateOptimalParameters(for: quality)
                try await reconfigureWithParameters(adjustedParams)
            } catch {
                logger.error("Failed to handle quality warning: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    private func updateUI(with guidance: GuidanceUpdate) {
        NotificationCenter.default.post(
            name: Notification.Name("UpdateScanningGuidance"),
            object: nil,
            userInfo: [
                "message": guidance.message,
                "progress": guidance.progress,
                "action": guidance.suggestedAction as Any,
                "visualGuide": guidance.visualGuide as Any
            ]
        )
    }
}