import Foundation
import ARKit
import Combine
import CoreImage
import os.log
import CoreMotion

enum ScanningMode {
    case lidar
    case photogrammetry
    case hybrid
}

enum ScanningError: Error {
    case qualityBelowThreshold
    case deviceNotSupported
    case insufficientLighting
    case excessiveMotion
    case processingFailed
    case sessionConfigurationFailed
    case noDepthDataAvailable
    case noSegmentationDataAvailable
}

final class ScanningController: ObservableObject {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningController")
    private let motionManager = CMMotionManager()
    private let qualityMonitor = ScanQualityMonitor()
    private let frameBuffer = FrameBuffer(capacity: 30)
    private var cancellables = Set<AnyCancellable>()
    
    @Published private(set) var currentMode: ScanningMode = .lidar
    @Published private(set) var qualityScore: Double = 0.0
    @Published private(set) var isProcessing = false
    @Published private(set) var recoveryStatus: RecoveryStatus = .none
    
    private var fallbackAttempts = 0
    private let maxFallbackAttempts = 3
    private var lastQualityCheck = Date()
    private let qualityCheckInterval: TimeInterval = 0.5
    
    init() {
        setupQualityMonitoring()
        setupMotionMonitoring()
    }
    
    func startScanning() async throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ScanningError.deviceNotSupported
        }
        
        fallbackAttempts = 0
        currentMode = determineOptimalScanningMode()
        await startScanningMode()
    }
    
    private func setupMotionMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates()
    }
    
    private func startScanningMode() async {
        isProcessing = true
        
        do {
            switch currentMode {
            case .lidar:
                try await startLiDARScanning()
            case .photogrammetry:
                try await startPhotogrammetryScanning()
            case .hybrid:
                try await startHybridScanning()
            }
        } catch {
            logger.error("Scanning failed in mode \(self.currentMode): \(error.localizedDescription)")
            await handleScanningFailure(error)
        }
    }
    
    private func startLiDARScanning() async throws {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.sceneReconstruction = .mesh
        
        try await configureScanningSession(configuration)
    }
    
    private func startPhotogrammetryScanning() async throws {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.personSegmentationWithDepth]
        
        try await configureScanningSession(configuration)
    }
    
    private func startHybridScanning() async throws {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth, .personSegmentationWithDepth]
        configuration.sceneReconstruction = .mesh
        
        try await configureScanningSession(configuration)
    }
    
    private func configureScanningSession(_ configuration: ARConfiguration) async throws {
        // Configure frame buffering
        frameBuffer.clear()
        
        // Start session with error handling
        do {
            try await withCheckedThrowingContinuation { continuation in
                ARSession().run(configuration, options: [.resetTracking, .removeExistingAnchors])
                continuation.resume()
            }
        } catch {
            throw ScanningError.sessionConfigurationFailed
        }
    }
    
    private func handleScanningFailure(_ error: Error) async {
        if fallbackAttempts < maxFallbackAttempts {
            fallbackAttempts += 1
            let backoffDelay = pow(2.0, Double(fallbackAttempts))
            
            recoveryStatus = .attempting(attempt: fallbackAttempts, max: maxFallbackAttempts)
            
            try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
            
            // Try fallback modes
            switch currentMode {
            case .lidar:
                currentMode = .hybrid
            case .hybrid:
                currentMode = .photogrammetry
            case .photogrammetry:
                recoveryStatus = .failed(error: error)
                return
            }
            
            await startScanningMode()
        } else {
            recoveryStatus = .failed(error: error)
        }
    }
    
    func processFrame(_ frame: ARFrame) async throws {
        // Buffer frame for potential recovery
        frameBuffer.add(frame)
        
        // Process frame based on current mode with sensor fusion
        switch currentMode {
        case .lidar:
            try await processLiDARFrame(frame)
        case .photogrammetry:
            try await processPhotogrammetryFrame(frame)
        case .hybrid:
            try await processHybridFrame(frame)
        }
        
        // Check quality and trigger recovery if needed
        await checkQualityAndRecover(frame)
    }
    
    private func processLiDARFrame(_ frame: ARFrame) async throws {
        guard let depthData = frame.sceneDepth?.depthMap else {
            throw ScanningError.noDepthDataAvailable
        }
        
        // Enhance depth data with IMU fusion
        if let motion = motionManager.deviceMotion {
            try await enhanceDepthWithIMU(depthData, motion: motion)
        }
    }
    
    private func processPhotogrammetryFrame(_ frame: ARFrame) async throws {
        guard let segmentationBuffer = frame.segmentationBuffer else {
            throw ScanningError.noSegmentationDataAvailable
        }
        
        // Process photogrammetry data
        try await processPhotogrammetryData(frame, segmentation: segmentationBuffer)
    }
    
    private func processHybridFrame(_ frame: ARFrame) async throws {
        // Process both LiDAR and photogrammetry data
        async let lidarResult = processLiDARFrame(frame)
        async let photoResult = processPhotogrammetryFrame(frame)
        
        // Wait for both results and fuse data
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await lidarResult }
            group.addTask { try await photoResult }
            try await group.waitForAll()
        }
        
        try await fuseDataSources()
    }
    
    private func checkQualityAndRecover(_ frame: ARFrame) async {
        guard Date().timeIntervalSince(lastQualityCheck) >= qualityCheckInterval else { return }
        
        lastQualityCheck = Date()
        let quality = try? await qualityMonitor.assessQuality(frame)
        
        if let quality = quality, quality < QualityThresholds.minQuality {
            // Attempt quick recovery with recent frames
            if await attemptQuickRecovery() {
                recoveryStatus = .recovered
            } else {
                // If quick recovery fails, trigger mode fallback
                await handleScanningFailure(ScanningError.qualityBelowThreshold)
            }
        }
    }
    
    private func attemptQuickRecovery() async -> Bool {
        // Try to recover using buffered frames
        let recentFrames = frameBuffer.getRecentFrames(count: 5)
        
        for frame in recentFrames.reversed() {
            if try? await validateFrame(frame) {
                // Use this frame as recovery point
                try? await reprocessFromFrame(frame)
                return true
            }
        }
        
        return false
    }
    
    private func setupQualityMonitoring() {
        qualityMonitor.$qualityMetrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.handleQualityUpdate(metrics)
            }
            .store(in: &cancellables)
    }
    
    private func handleQualityUpdate(_ metrics: ScanQualityMetrics) {
        Task {
            do {
                let quality = metrics.overallQuality
                qualityScore = quality
                
                if quality < ScanningQualityThresholds.minQuality {
                    logger.warning("Quality below threshold: \(quality)")
                    
                    // Check if we need to switch scanning modes
                    if qualityTracker.isQualityConsistentlyLow {
                        // Try to improve quality before switching modes
                        if try await improveQuality() {
                            logger.info("Successfully improved scanning quality")
                            return
                        }
                        
                        // If quality can't be improved, switch modes
                        try await switchScanningMode()
                    } else {
                        // Provide guidance for quality improvement
                        await provideQualityGuidance(metrics)
                    }
                }
            } catch {
                logger.error("Error handling quality update: \(error.localizedDescription)")
                await handleScanningFailure(error)
            }
        }
    }

    private func improveQuality() async throws -> Bool {
        // Try different quality improvement strategies
        let strategies: [QualityImprovementStrategy] = [
            .adjustExposure,
            .increaseDensity,
            .enhanceLighting,
            .optimizeDistance
        ]
        
        for strategy in strategies {
            if try await applyQualityStrategy(strategy) {
                return true
            }
        }
        
        return false
    }

    private func applyQualityStrategy(_ strategy: QualityImprovementStrategy) async throws -> Bool {
        logger.info("Applying quality improvement strategy: \(strategy)")
        
        switch strategy {
        case .adjustExposure:
            return try await adjustCameraExposure()
        case .increaseDensity:
            return try await increasePointDensity()
        case .enhanceLighting:
            return try await suggestLightingImprovements()
        case .optimizeDistance:
            return try await optimizeScanningDistance()
        }
    }

    private func provideQualityGuidance(_ metrics: ScanQualityMetrics) async {
        // Analyze metrics to determine the most important improvement needed
        let guidance: String
        
        if metrics.pointDensity < ScanningQualityThresholds.minPointDensity {
            guidance = "Move the device closer to capture more detail"
        } else if metrics.surfaceCompleteness < ScanningQualityThresholds.surfaceCompleteness {
            guidance = "Ensure all areas are properly scanned"
        } else if metrics.noiseLevel > ScanningQualityThresholds.maxNoiseLevel {
            guidance = "Hold the device more steady"
        } else {
            guidance = "Continue scanning to improve quality"
        }
        
        await MainActor.run {
            self.guideMessage = guidance
        }
    }

    private enum QualityImprovementStrategy {
        case adjustExposure
        case increaseDensity
        case enhanceLighting
        case optimizeDistance
    }

    private func adjustCameraExposure() async throws -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return false
        }
        
        try await device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        if device.exposureMode == .locked {
            device.exposureMode = .continuousAutoExposure
            return true
        }
        
        return false
    }

    private func increasePointDensity() async throws -> Bool {
        // Adjust scanning parameters for higher density
        processingParameters.searchRadius *= 0.8
        processingParameters.spatialSigma *= 0.9
        
        // Wait for next frame to evaluate improvement
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        return true
    }

    private func suggestLightingImprovements() async throws -> Bool {
        // Check current lighting conditions
        guard let frame = await getCurrentFrame(),
              let lightEstimate = frame.lightEstimate else {
            return false
        }
        
        let isLowLight = lightEstimate.ambientIntensity < 100
        if isLowLight {
            await MainActor.run {
                self.guideMessage = "Move to a better lit area"
            }
            return true
        }
        
        return false
    }

    private func optimizeScanningDistance() async throws -> Bool {
        guard let frame = await getCurrentFrame(),
              let depthData = frame.sceneDepth?.depthMap else {
            return false
        }
        
        let averageDepth = try calculateAverageDepth(depthData)
        let optimalRange = (0.3...0.8) // 30cm to 80cm
        
        if !optimalRange.contains(averageDepth) {
            let guidance = averageDepth < optimalRange.lowerBound
                ? "Move further from the subject"
                : "Move closer to the subject"
            
            await MainActor.run {
                self.guideMessage = guidance
            }
            return true
        }
        
        return false
    }

    private func calculateAverageDepth(_ depthMap: CVPixelBuffer) throws -> Float {
        var totalDepth: Float = 0
        var validPoints = 0
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            throw ScanningError.processingFailed
        }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        for y in 0..<height {
            for x in 0..<width {
                let depth = baseAddress.advanced(by: y * bytesPerRow + x * 4)
                    .assumingMemoryBound(to: Float.self)
                    .pointee
                
                if depth > 0 {
                    totalDepth += depth
                    validPoints += 1
                }
            }
        }
        
        return validPoints > 0 ? totalDepth / Float(validPoints) : 0
    }

    private func startLiDARScanning() async throws {
        logger.info("Starting LiDAR scanning")
        
        guard let arSession = ARSession() else {
            throw ScanningError.deviceNotSupported
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        // Configure environment assessment
        if #available(iOS 16.0, *) {
            configuration.environmentTexturing = .automatic
        }
        
        arSession.run(configuration)
        
        // Start quality monitoring
        qualityMonitor.startMonitoring()
        
        for try await frame in arSession.frames {
            guard let depthMap = frame.sceneDepth?.depthMap,
                  let confidenceMap = frame.sceneDepth?.confidenceMap else {
                continue
            }
            
            // Validate frame quality
            let frameQuality = try await validateFrameQuality(depthMap: depthMap, confidenceMap: confidenceMap)
            if frameQuality < 0.7 {
                logger.warning("Frame quality below threshold: \(frameQuality)")
                continue
            }
            
            // Process depth data and generate mesh
            let meshData = try await processMeshData(frame: frame)
            
            // Validate mesh quality
            let meshQuality = try await validateMeshQuality(meshData)
            if meshQuality < 0.8 {
                throw ScanningError.qualityBelowThreshold
            }
            
            // Update progress
            await updateScanProgress(meshData)
        }
    }
    
    private func validateFrameQuality(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer) async throws -> Double {
        let depthQuality = try ImageQualityAnalyzer.analyzeDepthQuality(depthMap)
        let confidenceScore = try ImageQualityAnalyzer.analyzeConfidence(confidenceMap)
        
        return (depthQuality + confidenceScore) / 2.0
    }
    
    private func processMeshData(frame: ARFrame) async throws -> MeshData {
        let meshProcessor = MeshProcessor()
        return try await meshProcessor.processFrame(frame)
    }
    
    private func validateMeshQuality(_ meshData: MeshData) async throws -> Double {
        let metrics = try await MeshQualityAnalyzer.analyzeMesh(meshData)
        return metrics.qualityScore
    }
    
    private func updateScanProgress(_ meshData: MeshData) async {
        // Update scan progress and UI
        let progress = calculateProgress(meshData)
        await MainActor.run {
            self.scanProgress = progress
        }
    }
    
    private func startPhotogrammetryScanning() async throws {
        logger.info("Starting Photogrammetry scanning")
        
        let captureSession = AVCaptureSession()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw ScanningError.deviceNotSupported
        }
        
        captureSession.addInput(input)
        
        // Configure camera for high quality capture
        try await device.lockForConfiguration()
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        device.unlockForConfiguration()
        
        // Setup output
        let photoOutput = AVCapturePhotoOutput()
        captureSession.addOutput(photoOutput)
        
        // Start capture session
        captureSession.startRunning()
        
        // Initialize photogrammetry processor
        let photogrammetryProcessor = PhotogrammetryManager()
        
        // Capture multiple angles
        for angle in stride(from: 0, to: 360, by: 45) {
            // Guide user to move to next angle
            await guideUserToAngle(angle)
            
            // Capture and process image
            let photoSettings = AVCapturePhotoSettings()
            let photoData = try await capturePhoto(with: photoSettings, using: photoOutput)
            
            // Validate image quality
            let imageQuality = try await validateImageQuality(photoData)
            if imageQuality < 0.7 {
                logger.warning("Image quality below threshold: \(imageQuality)")
                continue
            }
            
            // Process image for photogrammetry
            try await photogrammetryProcessor.addImage(photoData)
            
            // Update progress
            await updatePhotogrammetryProgress(angle: angle)
        }
        
        // Generate 3D model from captured images
        let meshData = try await photogrammetryProcessor.generateMesh()
        
        // Validate final mesh quality
        let meshQuality = try await validateMeshQuality(meshData)
        if meshQuality < 0.8 {
            throw ScanningError.qualityBelowThreshold
        }
        
        captureSession.stopRunning()
    }
    
    private func capturePhoto(with settings: AVCapturePhotoSettings, using output: AVCapturePhotoOutput) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let handler = PhotoCaptureDelegate { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            output.capturePhoto(with: settings, delegate: handler)
        }
    }
    
    private func validateImageQuality(_ imageData: Data) async throws -> Double {
        guard let image = CIImage(data: imageData) else {
            throw ScanningError.processingFailed
        }
        
        let analyzer = ImageQualityAnalyzer()
        let metrics = try await analyzer.analyzeImage(image)
        
        return metrics.overallQuality
    }
    
    private func guideUserToAngle(_ angle: Int) async {
        await MainActor.run {
            // Update UI to guide user to the next angle
            self.currentAngle = angle
            self.guideMessage = "Please move to \(angle)° angle"
        }
        // Add delay to allow user to move
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
    
    @MainActor private var currentAngle: Int = 0
    @MainActor private var guideMessage: String = ""
    
    private func updatePhotogrammetryProgress(angle: Int) async {
        let progress = Double(angle) / 360.0
        await MainActor.run {
            self.scanProgress = progress
        }
    }
    
    private func startHybridScanning() async throws {
        logger.info("Starting Hybrid scanning")
        
        // Start both LiDAR and photogrammetry sessions in parallel
        async let lidarData = captureLiDARData()
        async let photoData = capturePhotogrammetryData()
        
        // Wait for both capture sessions to complete
        let (meshFromLiDAR, meshFromPhoto) = try await (lidarData, photoData)
        
        // Initialize data fusion processor
        let fusionProcessor = DataFusionProcessor()
        
        // Fuse both mesh data for enhanced accuracy
        let fusedMesh = try await fusionProcessor.fuseMeshes(
            lidarMesh: meshFromLiDAR,
            photoMesh: meshFromPhoto,
            qualityWeights: calculateQualityWeights(
                lidarQuality: meshFromLiDAR.confidence,
                photoQuality: meshFromPhoto.confidence
            )
        )
        
        // Validate fused mesh quality
        let fusedQuality = try await validateMeshQuality(fusedMesh)
        if fusedQuality < 0.85 {
            throw ScanningError.qualityBelowThreshold
        }
        
        // Post-process the fused mesh
        let finalMesh = try await postProcessMesh(fusedMesh)
        
        // Export the final mesh
        try await MeshExporter.shared.exportMesh(finalMesh, format: .usdz)
    }
    
    private func captureLiDARData() async throws -> MeshData {
        var meshData: MeshData?
        var error: Error?
        
        // Create child task for LiDAR scanning
        let task = Task {
            do {
                try await startLiDARScanning()
                // Get the final mesh data from LiDAR scanning
                return try await MeshProcessor.shared.getCurrentMesh()
            } catch let captureError {
                throw captureError
            }
        }
        
        // Wait for LiDAR scanning to complete or timeout
        let timeoutInSeconds: UInt64 = 30
        do {
            meshData = try await withTimeout(seconds: timeoutInSeconds) {
                try await task.value
            }
        } catch {
            logger.error("LiDAR capture failed: \(error.localizedDescription)")
            throw error
        }
        
        guard let finalMeshData = meshData else {
            throw ScanningError.processingFailed
        }
        
        return finalMeshData
    }
    
    private func capturePhotogrammetryData() async throws -> MeshData {
        var meshData: MeshData?
        var error: Error?
        
        // Create child task for photogrammetry
        let task = Task {
            do {
                try await startPhotogrammetryScanning()
                // Get the final mesh data from photogrammetry
                return try await PhotogrammetryManager.shared.getCurrentMesh()
            } catch let captureError {
                throw captureError
            }
        }
        
        // Wait for photogrammetry to complete or timeout
        let timeoutInSeconds: UInt64 = 45
        do {
            meshData = try await withTimeout(seconds: timeoutInSeconds) {
                try await task.value
            }
        } catch {
            logger.error("Photogrammetry capture failed: \(error.localizedDescription)")
            throw error
        }
        
        guard let finalMeshData = meshData else {
            throw ScanningError.processingFailed
        }
        
        return finalMeshData
    }
    
    private func calculateQualityWeights(lidarQuality: [Float], photoQuality: [Float]) -> [Float] {
        // Combine quality metrics from both sources
        return zip(lidarQuality, photoQuality).map { lidar, photo in
            // Weight calculation based on confidence values
            let lidarWeight = Float(0.7) // LiDAR typically more accurate
            let photoWeight = Float(0.3)
            return (lidar * lidarWeight + photo * photoWeight) / (lidarWeight + photoWeight)
        }
    }
    
    private func postProcessMesh(_ mesh: MeshData) async throws -> MeshData {
        // Apply post-processing steps
        let processor = MeshProcessor()
        
        // Remove noise and optimize mesh
        var processedMesh = try await processor.removeNoise(from: mesh)
        processedMesh = try await processor.optimizeMesh(processedMesh)
        
        // Validate final quality
        let finalQuality = try await validateMeshQuality(processedMesh)
        if finalQuality < 0.8 {
            throw ScanningError.qualityBelowThreshold
        }
        
        return processedMesh
    }
    
    private func withTimeout<T>(seconds: UInt64, operation: () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw ScanningError.processingFailed
            }
            
            guard let result = try await group.next() else {
                throw ScanningError.processingFailed
            }
            
            group.cancelAll()
            return result
        }
    }
    
    // Update scanning mode selection with adaptive strategy
    private func determineOptimalScanningMode() -> ScanningMode {
        // Check device capabilities
        let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let hasTrueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
        
        if hasLiDAR {
            return .lidar
        } else if hasTrueDepth {
            return .hybrid
        } else {
            return .photogrammetry
        }
    }

    private func updateQualityMetrics(_ frame: ARFrame) async throws {
        guard isScanning else { return }
        
        // Get depth and confidence data
        guard let depthMap = frame.sceneDepth?.depthMap,
              let confidenceMap = frame.sceneDepth?.confidenceMap else {
            throw ScanningError.processingFailed
        }
        
        // Calculate frame quality metrics
        let frameQuality = try await validateFrameQuality(
            depthMap: depthMap,
            confidenceMap: confidenceMap
        )
        
        // Update quality tracking
        qualityTracker.addFrameQuality(frameQuality)
        
        // Check if quality is consistently low
        if qualityTracker.isQualityConsistentlyLow {
            handleLowQuality()
        }
    }

    private func handleLowQuality() {
        // If quality is consistently low, try fallback strategies
        fallbackAttempts += 1
        
        if fallbackAttempts <= maxFallbackAttempts {
            switch currentScanningMode {
            case .lidar:
                // Switch to hybrid mode if LiDAR quality is poor
                currentScanningMode = .hybrid
                logger.info("Switching to hybrid scanning mode due to low quality")
                
            case .photogrammetry:
                // Adjust photogrammetry parameters
                adjustPhotogrammetrySettings()
                logger.info("Adjusting photogrammetry settings due to low quality")
                
            case .hybrid:
                // Fine-tune fusion weights
                adjustFusionWeights()
                logger.info("Adjusting fusion weights due to low quality")
            }
            
            // Notify the UI to update guidance
            NotificationCenter.default.post(
                name: .scanningModeChanged,
                object: nil,
                userInfo: ["mode": currentScanningMode]
            )
        }
    }

    private func adjustPhotogrammetrySettings() {
        // Adjust capture parameters based on current conditions
        let currentLight = getCurrentLightingConditions()
        
        photoSettings.update(
            exposure: calculateOptimalExposure(for: currentLight),
            focus: calculateOptimalFocus(),
            iso: calculateOptimalISO(for: currentLight)
        )
    }

    private func adjustFusionWeights() {
        // Analyze recent quality metrics
        let recentMetrics = qualityTracker.getRecentMetrics(count: 10)
        let lidarQuality = recentMetrics.map { $0.lidarConfidence }.reduce(0, +) / Float(recentMetrics.count)
        let photoQuality = recentMetrics.map { $0.photoConfidence }.reduce(0, +) / Float(recentMetrics.count)
        
        // Update fusion weights based on quality analysis
        fusionProcessor.configureFusion(FusionConfiguration(
            lidarWeight: lidarQuality / (lidarQuality + photoQuality),
            photoWeight: photoQuality / (lidarQuality + photoQuality)
        ))
    }

    // Quality tracking helper class
    private class QualityTracker {
        private var recentQualities: [(timestamp: TimeInterval, quality: Float)] = []
        private let qualityThreshold: Float = 0.7
        private let consistencyWindow: TimeInterval = 3.0 // 3 seconds
        
        var isQualityConsistentlyLow: Bool {
            guard recentQualities.count >= 3 else { return false }
            
            let currentTime = CACurrentMediaTime()
            let recentSamples = recentQualities.filter {
                currentTime - $0.timestamp < consistencyWindow
            }
            
            let averageQuality = recentSamples.map { $0.quality }.reduce(0, +) / Float(recentSamples.count)
            return averageQuality < qualityThreshold
        }
        
        func addFrameQuality(_ quality: Float) {
            let currentTime = CACurrentMediaTime()
            recentQualities.append((currentTime, quality))
            
            // Remove old samples
            recentQualities = recentQualities.filter {
                currentTime - $0.timestamp < consistencyWindow
            }
        }
        
        func getRecentMetrics(count: Int) -> [(lidarConfidence: Float, photoConfidence: Float)] {
            // Implementation for retrieving recent quality metrics
            return []  // Placeholder
        }
    }
    
    private func handleScanningError(_ error: Error) async {
        logger.error("Scanning error encountered: \(error.localizedDescription)")
        
        let recovery = ScanningErrorRecovery()
        if await recovery.attemptRecovery(from: error) {
            logger.info("Successfully recovered from error")
            
            // Reset scanning parameters
            processingParameters = ProcessingParameters(
                searchRadius: 0.01,
                spatialSigma: 0.005,
                confidenceThreshold: 0.7
            )
            
            // Restart scanning with adjusted parameters
            await startScanningMode()
        } else {
            logger.error("Error recovery failed")
            await handleUnrecoverableError(error)
        }
    }

    private func handleUnrecoverableError(_ error: Error) async {
        fallbackAttempts += 1
        
        if fallbackAttempts < maxFallbackAttempts {
            // Try switching scanning modes
            switch currentMode {
            case .lidar:
                currentMode = .hybrid
                logger.info("Switching to hybrid mode after unrecoverable error")
            case .hybrid:
                currentMode = .photogrammetry
                logger.info("Switching to photogrammetry mode after unrecoverable error")
            case .photogrammetry:
                throw ScanningError.processingFailed
            }
            
            // Initialize guidance system with new mode
            guidanceSystem = ScanningGuidanceSystem()
            await guidanceSystem.startGuidance()
            
            // Reset quality monitoring
            qualityMonitor.stopMonitoring()
            qualityMonitor = ScanQualityMonitor()
            qualityMonitor.startMonitoring()
            
            // Restart scanning with new mode
            await startScanningMode()
        } else {
            // Notify user of scanning failure
            NotificationCenter.default.post(
                name: Notification.Name("ScanningFailed"),
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
}

// MARK: - Supporting Types
struct ScanQualityMetrics {
    let overallQuality: Double
}

class ScanQualityMonitor: ObservableObject {
    @Published var qualityMetrics = ScanQualityMetrics(overallQuality: 1.0)
    
    private var monitoringTimer: Timer?
    
    func startMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Implement actual quality measurements here
            let quality = ScanQualityMetrics(overallQuality: 0.9)
            self.qualityMetrics = quality
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}

struct MeshData {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    let normals: [SIMD3<Float>]
    let confidence: [Float]
}

@MainActor
private var scanProgress: Double = 0.0 {
    didSet {
        objectWillChange.send()
    }
}

private func calculateProgress(_ meshData: MeshData) -> Double {
    // Calculate scan coverage and completeness
    let coverage = Double(meshData.vertices.count) / targetVertexCount
    return min(max(coverage, 0.0), 1.0)
}

// Add PhotoCaptureDelegate
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void
    
    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            completion(.failure(ScanningError.processingFailed))
            return
        }
        
        completion(.success(imageData))
    }
}

enum RecoveryStatus {
    case none
    case attempting(attempt: Int, max: Int)
    case recovered
    case failed(error: Error)
}

class FrameBuffer {
    private var frames: [ARFrame] = []
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func add(_ frame: ARFrame) {
        frames.append(frame)
        if frames.count > capacity {
            frames.removeFirst()
        }
    }
    
    func getRecentFrames(count: Int) -> [ARFrame] {
        let start = max(0, frames.count - count)
        return Array(frames[start...])
    }
    
    func clear() {
        frames.removeAll()
    }
}

struct QualityThresholds {
    static let minQuality: Float = 0.7
    static let minPointDensity: Float = 100.0
    static let minFeatureCount: Int = 100
}
