import ARKit
import Combine
import Dependencies
import Foundation
import Metal
import os.log
import RealityKit

private let logger = Logger(subsystem: "com.xcalp.clinic", category: "scanning")
private let meshProcessor = try! MeshProcessor()

public struct ScanningClient {
    public var checkDeviceCapabilities: @Sendable () async throws -> Bool
    public var monitorScanQuality: @Sendable () -> AsyncStream<ScanningFeature.ScanQuality>
    public var captureScan: @Sendable () async throws -> Data
    public var monitorLidarStatus: @Sendable () -> AsyncStream<ScanningFeature.LidarStatus>
    public var initializeLidar: @Sendable () async throws -> ARSession
    
    public static let liveValue = Self.live
    
    static let live = ScanningClient(
        checkDeviceCapabilities: {
            #if targetEnvironment(simulator)
            return false
            #else
            let perfID = PerformanceMonitor.shared.startMeasuring(
                "deviceCapabilityCheck",
                category: "scanning"
            )
            
            // Check for LiDAR Scanner
            if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                logger.error("Device does not support LiDAR scanning")
                return false
            }
            
            // Check for mesh reconstruction
            if !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                logger.error("Device does not support mesh reconstruction")
                return false
            }
            
            // Check for person segmentation
            if !ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                logger.error("Device does not support person segmentation")
                return false
            }
            
            PerformanceMonitor.shared.endMeasuring(
                "deviceCapabilityCheck",
                signpostID: perfID,
                category: "scanning"
            )
            
            return true
            #endif
        },
        monitorScanQuality: {
            AsyncStream { continuation in
                let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
                let cancellable = timer.sink { _ in
                    let perfID = PerformanceMonitor.shared.startMeasuring(
                        "scanQualityCheck",
                        category: "scanning"
                    )
                    
                    // Check performance requirements
                    let meetsPerformance = PerformanceMonitor.shared.meetsPerformanceRequirements()
                    let quality: ScanningFeature.ScanQuality = meetsPerformance ? .good : .poor
                    
                    AnalyticsService.shared.logAction(
                        "scanQualityUpdate",
                        category: "scanning",
                        properties: ["quality": quality.rawValue]
                    )
                    
                    continuation.yield(quality)
                    
                    PerformanceMonitor.shared.endMeasuring(
                        "scanQualityCheck",
                        signpostID: perfID,
                        category: "scanning"
                    )
                }
                
                continuation.onTermination = { _ in
                    cancellable.cancel()
                }
            }
        },
        captureScan: {
            let perfID = PerformanceMonitor.shared.startMeasuring(
                "scanCapture",
                category: "scanning"
            )
            
            let session = try await initializeLidarSession()
            
            // Wait for mesh data to be generated
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Get all mesh anchors
            let meshAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
            
            guard !meshAnchors.isEmpty else {
                logger.error("No mesh data available after scan")
                throw ScanningFeature.ScanningError.noMeshDataAvailable
            }
            
            // Convert mesh data to raw format
            var meshData = Data()
            for anchor in meshAnchors {
                let geometry = anchor.geometry
                
                // Add vertex positions
                let vertices = geometry.vertices
                meshData.append(contentsOf: vertices.buffer.contents().assumingMemoryBound(to: Float.self), count: vertices.count * MemoryLayout<Float>.size)
                
                // Add vertex normals
                let normals = geometry.normals
                meshData.append(contentsOf: normals.buffer.contents().assumingMemoryBound(to: Float.self), count: normals.count * MemoryLayout<Float>.size)
                
                // Add face indices
                let faces = geometry.faces
                meshData.append(contentsOf: faces.buffer.contents().assumingMemoryBound(to: Int32.self), count: faces.count * MemoryLayout<Int32>.size)
            }
            
            session.pause()
            
            // Process the captured mesh
            let processedMesh = try await meshProcessor.processMesh(meshData)
            
            // Log metrics
            AnalyticsService.shared.logScanMetrics(
                originalVertexCount: processedMesh.metrics.originalVertexCount,
                optimizedVertexCount: processedMesh.metrics.optimizedVertexCount,
                processingTime: processedMesh.metrics.processingTime,
                quality: processedMesh.quality
            )
            
            PerformanceMonitor.shared.endMeasuring(
                "scanCapture",
                signpostID: perfID,
                category: "scanning"
            )
            
            // Encode processed mesh for storage
            let encoder = JSONEncoder()
            return try encoder.encode(ScanData(
                mesh: processedMesh,
                settings: .default,
                deviceInfo: .current,
                environmentInfo: .current
            ))
        },
        monitorLidarStatus: {
            AsyncStream { continuation in
                Task {
                    let maxRetries = 3
                    var currentRetry = 0
                    var session: ARSession?
                    
                    while currentRetry < maxRetries {
                        do {
                            session = try await initializeLidarSession()
                            continuation.yield(.ready)
                            break
                        } catch {
                            currentRetry += 1
                            logger.error("LiDAR initialization failed (attempt \(currentRetry)/\(maxRetries)): \(error.localizedDescription)")
                            continuation.yield(.error(error))
                            
                            if currentRetry < maxRetries {
                                // Exponential backoff
                                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(currentRetry))) * 1_000_000_000)
                            }
                        }
                    }
                    
                    if currentRetry == maxRetries {
                        continuation.yield(.failed)
                    }
                    
                    continuation.onTermination = { _ in
                        session?.pause()
                    }
                }
            }
        },
        initializeLidar: {
            try await initializeLidarSession()
        }
    )
    
    public static let testValue = ScanningClient(
        checkDeviceCapabilities: { true },
        monitorScanQuality: { AsyncStream { continuation in
            continuation.yield(.good)
            continuation.finish()
        }},
        captureScan: { Data() },
        monitorLidarStatus: { AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        }},
        initializeLidar: { ARSession() }
    )
}

extension DependencyValues {
    public var scanningClient: ScanningClient {
        get { self[ScanningClient.self] }
        set { self[ScanningClient.self] = newValue }
    }
}

private func initializeLidarSession() async throws -> ARSession {
    let session = ARSession()
    
    guard let configuration = ARWorldTrackingConfiguration.new(
        with: [.sceneDepth, .smoothedSceneDepth],
        sceneReconstruction: .mesh
    ) else {
        logger.error("Failed to create AR configuration")
        throw ScanningFeature.ScanningError.captureSetupFailed
    }
    
    // Set up error handling
    let errorHandler = { (error: Error) in
        logger.error("AR session failed: \(error.localizedDescription)")
    }
    
    session.delegateQueue = DispatchQueue.global(qos: .userInitiated)
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    
    // Wait for tracking to stabilize
    try await withTimeout(seconds: 5) {
        await withCheckedContinuation { continuation in
            var observation: NSKeyValueObservation?
            observation = session.observe(\.currentFrame?.camera.trackingState) { session, _ in
                guard let frame = session.currentFrame else { return }
                
                switch frame.camera.trackingState {
                case .normal:
                    observation?.invalidate()
                    continuation.resume()
                case .limited(let reason):
                    logger.warning("Limited tracking: \(reason)")
                case .notAvailable:
                    logger.error("Tracking not available")
                }
            }
        }
    }
    
    return session
}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ScanningFeature.ScanningError.timeout
        }
        
        let result = try await group.next()
        group.cancelAll()
        return result!
    }
}

private extension ARWorldTrackingConfiguration {
    static func new(
        with frameSemantics: ARConfiguration.FrameSemantics,
        sceneReconstruction: ARWorldTrackingConfiguration.SceneReconstruction
    ) -> ARWorldTrackingConfiguration? {
        let configuration = ARWorldTrackingConfiguration()
        
        guard Self.supportsFrameSemantics(frameSemantics) else { return nil }
        configuration.frameSemantics = frameSemantics
        
        if Self.supportsSceneReconstruction(sceneReconstruction) {
            configuration.sceneReconstruction = sceneReconstruction
        }
        
        return configuration
    }
}
