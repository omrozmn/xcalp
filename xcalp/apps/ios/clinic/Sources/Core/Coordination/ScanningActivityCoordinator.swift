import ARKit
import Combine
import Metal
import os.log

public class ScanningActivityCoordinator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningCoordinator")
    private let device: MTLDevice
    private let session: ARSession
    private let capabilities: DeviceCapabilities
    
    private let meshAnalyzer: MeshQualityAnalyzer
    private let lightingAnalyzer: LightingAnalyzer
    private let postProcessor: ScanningPostProcessor
    private let cache: ScanningCache
    private let dataStore: ScanningDataStore
    
    private var currentSession: UUID?
    private var qualityAssessment: QualityAssessment?
    private var scanningMetrics: [ScanningMetric] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Activity state
    private var isScanning = false
    private var processingQueue = DispatchQueue(label: "com.xcalp.scanning.processing")
    private let updateInterval: TimeInterval = 0.1
    private var lastUpdateTime = Date()
    
    // Quality monitoring
    private var qualityThreshold: Float
    private var consecutiveLowQualityFrames = 0
    private let maxLowQualityFrames = 30
    
    // Performance monitoring
    private var performanceMetrics = CurrentValueSubject<ResourceMetrics, Never>(ResourceMetrics())
    private let adaptiveQualityManager = AdaptiveQualityManager.shared
    
    public init() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CoordinationError.metalDeviceNotAvailable
        }
        self.device = device
        
        // Initialize ARSession
        self.session = ARSession()
        
        // Detect device capabilities
        let detector = DeviceCapabilityDetector.shared
        self.capabilities = await detector.detectCapabilities()
        
        // Initialize core components
        self.meshAnalyzer = try MeshQualityAnalyzer(device: device)
        self.lightingAnalyzer = try LightingAnalyzer()
        self.postProcessor = try ScanningPostProcessor(device: device)
        self.cache = try ScanningCache(device: device)
        self.dataStore = ScanningDataStore.shared
        
        // Set initial quality threshold
        self.qualityThreshold = AppConfiguration.Performance.Scanning.minFeaturePreservation
        
        // Configure session
        try await configureARSession()
        
        // Set up monitoring
        setupMonitoring()
    }
    
    public func startScanning(configuration: ScanningConfiguration) async throws {
        guard !isScanning else {
            throw CoordinationError.scanningAlreadyInProgress
        }
        
        // Create new session with state persistence
        currentSession = UUID()
        let sessionConfig = configuration.toDict()
        
        try await dataStore.createScanningSession(
            mode: configuration.mode,
            configuration: sessionConfig,
            timestamp: Date()
        )
        
        // Configure scanning pipeline
        isScanning = true
        scanningMetrics.removeAll()
        consecutiveLowQualityFrames = 0
        
        // Set up state recovery point
        try await persistSessionState(sessionID: currentSession!)
        
        // Configure and start AR session with error recovery
        try await configureARSession(for: configuration)
        session.run(createARConfiguration(for: configuration))
        
        // Start monitoring with adaptive thresholds
        setupQualityMonitoring(configuration.mode)
        setupEnvironmentalMonitoring()
    }
    
    public func stopScanning() async throws {
        guard isScanning else { return }
        guard let sessionID = currentSession else {
            throw CoordinationError.noActiveSession
        }
        
        isScanning = false
        session.pause()
        
        // Process final scan
        if let finalScan = try await processCurrentScan() {
            try await postProcessor.processScan(
                finalScan,
                options: ProcessingOptions()
            )
        }
        
        // Update session status
        try await dataStore.updateSessionStatus(
            sessionID,
            status: .completed
        )
        
        // Clear current session
        currentSession = nil
        
        // Notify observers
        NotificationCenter.default.post(
            name: .scanningDidStop,
            object: self
        )
        
        logger.info("Stopped scanning session: \(sessionID.uuidString)")
    }
    
    public func processFrame(_ frame: ARFrame) async throws {
        guard isScanning else { return }
        guard Date().timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        
        // Analyze frame quality
        let lightingAnalysis = await lightingAnalyzer.analyzeLighting(frame)
        
        if !lightingAnalysis.isAcceptable {
            consecutiveLowQualityFrames += 1
            if consecutiveLowQualityFrames >= maxLowQualityFrames {
                throw ScanningError.insufficientLighting
            }
            return
        }
        
        // Reset counter if quality is good
        consecutiveLowQualityFrames = 0
        
        // Process frame
        try await processingQueue.async {
            // Extract mesh data
            if let meshAnchor = frame.anchors.first(where: { $0 is ARMeshAnchor }) as? ARMeshAnchor {
                let quality = try await self.analyzeMeshQuality(meshAnchor)
                self.qualityAssessment = quality
                
                // Cache frame data if quality is acceptable
                if quality.isAcceptable {
                    try await self.cacheFrameData(frame, quality: quality)
                }
                
                // Update metrics
                self.updateMetrics(frame: frame, quality: quality)
            }
        }
        
        lastUpdateTime = Date()
    }
    
    public func exportScan(
        sessionID: UUID,
        format: ExportFormat,
        destination: URL
    ) async throws {
        guard let scan = try await loadScan(sessionID: sessionID) else {
            throw CoordinationError.scanNotFound
        }
        
        // Process and export scan
        let processedScan = try await postProcessor.processScan(
            scan,
            options: ProcessingOptions()
        )
        
        try await postProcessor.exportScan(
            processedScan,
            format: format,
            destination: destination
        )
        
        logger.info("Exported scan \(sessionID.uuidString) to \(destination.path)")
    }
    
    // MARK: - Private Methods
    
    private func configureARSession() async throws {
        session.delegate = self
        
        // Check device support
        let support = DeviceCapabilityDetector.shared.checkScanningSupport()
        guard case .supported = support else {
            throw ScanningError.deviceNotSupported
        }
    }
    
    private func configureARSession(
        for configuration: ScanningConfiguration
    ) async throws {
        // Configure based on scanning mode
        switch configuration.mode {
        case .lidar:
            guard capabilities.hasLiDAR else {
                throw ScanningError.deviceNotSupported
            }
            // Configure LiDAR specific settings
            
        case .photogrammetry:
            // Configure photogrammetry specific settings
            break
            
        case .hybrid:
            // Configure hybrid mode settings
            break
        }
    }
    
    private func createARConfiguration(
        for configuration: ScanningConfiguration
    ) -> ARConfiguration {
        let arConfig = ARWorldTrackingConfiguration()
        
        // Configure features based on device capabilities
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            arConfig.sceneReconstruction = .mesh
        }
        
        arConfig.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        return arConfig
    }
    
    private func analyzeMeshQuality(_ meshAnchor: ARMeshAnchor) async throws -> QualityAssessment {
        let geometry = meshAnchor.geometry
        return try await meshAnalyzer.analyzeMesh(geometry)
    }
    
    private func cacheFrameData(
        _ frame: ARFrame,
        quality: QualityAssessment
    ) async throws {
        guard let sessionID = currentSession else { return }
        
        // Cache depth data
        if let depthData = frame.sceneDepth?.depthMap.texture() {
            await cache.cacheFrame(
                id: sessionID,
                depthData: depthData,
                confidenceData: frame.sceneDepth?.confidenceMap.texture() ?? Data()
            )
        }
    }
    
    private func updateMetrics(
        frame: ARFrame,
        quality: QualityAssessment
    ) {
        let timestamp = Date()
        
        // Create metrics
        let metrics = [
            ScanningMetric(
                name: "Quality",
                value: Double(quality.overallQuality.rawValue),
                unit: "%",
                timestamp: timestamp
            ),
            ScanningMetric(
                name: "FPS",
                value: 1.0 / frame.timestamp,
                unit: "fps",
                timestamp: timestamp
            )
        ]
        
        scanningMetrics.append(contentsOf: metrics)
        
        // Update performance metrics
        let performance = ResourceMetrics(
            cpuUsage: ProcessInfo.processInfo.systemCpuUsage,
            memoryUsage: ProcessInfo.processInfo.physicalMemory,
            gpuUtilization: 0.0,
            frameRate: 1.0 / frame.timestamp
        )
        
        performanceMetrics.send(performance)
    }
    
    private func setupMonitoring() {
        // Monitor performance metrics
        performanceMetrics
            .throttle(
                for: .seconds(1),
                scheduler: DispatchQueue.global(qos: .utility),
                latest: true
            )
            .sink { [weak self] metrics in
                Task {
                    // Update quality settings based on performance
                    await self?.adaptiveQualityManager.updateQualitySettings(
                        performance: metrics,
                        environment: EnvironmentMetrics(
                            lightingLevel: 1.0,
                            motionStability: 1.0,
                            surfaceComplexity: 0.5
                        )
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadScan(sessionID: UUID) async throws -> RawScanData? {
        // Implement scan loading from cache/storage
        return nil
    }
    
    private func persistSessionState(sessionID: UUID) async throws {
        let state = ScanningSessionState(
            id: sessionID,
            mode: currentMode,
            metrics: scanningMetrics,
            qualityThresholds: qualityThreshold,
            timestamp: Date()
        )
        try await dataStore.saveSessionState(state)
    }

    private func recoverSession(sessionID: UUID) async throws {
        guard let state = try await dataStore.loadSessionState(sessionID) else {
            throw CoordinationError.sessionNotFound
        }
        
        // Restore session state
        currentMode = state.mode
        scanningMetrics = state.metrics
        qualityThreshold = state.qualityThresholds
        
        // Resume from last known good state
        try await resumeScanning(from: state)
    }
}

// MARK: - ARSessionDelegate

extension ScanningActivityCoordinator: ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task {
            do {
                try await processFrame(frame)
            } catch {
                logger.error("Error processing frame: \(error.localizedDescription)")
            }
        }
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        logger.error("AR session failed: \(error.localizedDescription)")
        NotificationCenter.default.post(
            name: .scanningDidFail,
            object: self,
            userInfo: ["error": error]
        )
    }
}

// MARK: - Supporting Types

enum CoordinationError: Error {
    case metalDeviceNotAvailable
    case scanningAlreadyInProgress
    case noActiveSession
    case scanNotFound
}

extension Notification.Name {
    static let scanningDidStart = Notification.Name("scanningDidStart")
    static let scanningDidStop = Notification.Name("scanningDidStop")
    static let scanningDidFail = Notification.Name("scanningDidFail")
}