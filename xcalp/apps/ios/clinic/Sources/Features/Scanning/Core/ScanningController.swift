import Foundation
import ARKit
import Combine
import CoreImage
import os.log

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
}

final class ScanningController: ObservableObject {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningController")
    private var qualityMonitor = ScanQualityMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    @Published private(set) var currentMode: ScanningMode = .lidar
    @Published private(set) var qualityScore: Double = 0.0
    @Published private(set) var isProcessing = false
    
    private var fallbackAttempts = 0
    private let maxFallbackAttempts = 3
    
    init() {
        setupQualityMonitoring()
    }
    
    func startScanning() async throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ScanningError.deviceNotSupported
        }
        
        fallbackAttempts = 0
        currentMode = .lidar
        await startScanningMode()
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
    
    private func handleScanningFailure(_ error: Error) async {
        if fallbackAttempts < maxFallbackAttempts {
            fallbackAttempts += 1
            let backoffDelay = pow(2.0, Double(fallbackAttempts))
            
            try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
            
            switch currentMode {
            case .lidar:
                currentMode = .photogrammetry
            case .photogrammetry:
                currentMode = .hybrid
            case .hybrid:
                throw ScanningError.processingFailed
            }
            
            await startScanningMode()
        } else {
            throw ScanningError.processingFailed
        }
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
        qualityScore = metrics.overallQuality
        
        if metrics.overallQuality < 0.7 {
            logger.warning("Quality below threshold: \(metrics.overallQuality)")
            Task {
                await handleScanningFailure(ScanningError.qualityBelowThreshold)
            }
        }
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
