#if canImport(ARKit)
import ARKit
import RealityKit

public enum ARError: Error {
    case deviceNotSupported
    case trackingFailed
    case insufficientFeatures
    case excessiveMotion
    case insufficientLight
    case sessionFailed
    case meshGenerationFailed
    case calibrationRequired
    case scanQualityLow
    case processingFailed
}

public final class ARErrorHandler {
    public static let shared = ARErrorHandler()
    
    private let logger = XcalpLogger.shared
    private let performance = PerformanceMonitor.shared
    
    private init() {}
    
    // MARK: - Device Capability Check
    public func checkDeviceCapability() throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            logger.log(.error, message: "Device does not support AR world tracking")
            throw ARError.deviceNotSupported
        }
        
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            logger.log(.error, message: "Device does not support mesh reconstruction")
            throw ARError.deviceNotSupported
        }
    }
    
    // MARK: - Tracking State Handling
    public func handleTrackingState(_ state: ARCamera.TrackingState) throws {
        switch state {
        case .normal:
            return
        case .notAvailable:
            logger.log(.error, message: "AR tracking not available")
            throw ARError.trackingFailed
        case .limited(let reason):
            switch reason {
            case .initializing:
                // This is normal during startup, just log it
                logger.log(.info, message: "AR tracking initializing")
            case .excessiveMotion:
                throw ARError.excessiveMotion
            case .insufficientFeatures:
                throw ARError.insufficientFeatures
            case .relocalizing:
                logger.log(.warning, message: "AR session relocalizing")
            @unknown default:
                logger.log(.error, message: "Unknown tracking limitation")
                throw ARError.trackingFailed
            }
        }
    }
    
    // MARK: - Session Error Handling
    public func handleSessionError(_ error: Error) throws {
        logger.log(.error, message: "AR session failed: \(error.localizedDescription)")
        throw ARError.sessionFailed
    }
    
    // MARK: - Mesh Quality Validation
    public func validateMeshQuality(_ mesh: ARMeshAnchor) throws {
        // Check vertex count
        let vertexCount = mesh.geometry.vertices.count
        guard vertexCount >= 1000 else {
            logger.log(.error, message: "Insufficient mesh vertices: \(vertexCount)")
            throw ARError.scanQualityLow
        }
        
        // Check face count
        let faceCount = mesh.geometry.faces.count
        guard faceCount >= 500 else {
            logger.log(.error, message: "Insufficient mesh faces: \(faceCount)")
            throw ARError.scanQualityLow
        }
        
        // Check mesh confidence
        var averageConfidence: Float = 0
        mesh.geometry.classifications.forEach { confidence in
            averageConfidence += confidence.confidence
        }
        averageConfidence /= Float(mesh.geometry.classifications.count)
        
        guard averageConfidence >= 0.8 else {
            logger.log(.error, message: "Low mesh confidence: \(averageConfidence)")
            throw ARError.scanQualityLow
        }
    }
    
    // MARK: - Processing Validation
    public func validateProcessing(_ operation: String, duration: TimeInterval) throws {
        // Blueprint requirement: Processing time < 5s
        guard duration <= 5.0 else {
            logger.log(.error, message: "\(operation) exceeded time limit: \(duration)s")
            throw ARError.processingFailed
        }
        
        // Check memory usage
        let memoryUsage = performance.checkMemoryUsage()
        let memoryMB = Double(memoryUsage) / 1024.0 / 1024.0
        
        // Blueprint requirement: Memory < 200MB
        guard memoryMB <= 200.0 else {
            logger.log(.error, message: "Memory usage exceeded limit: \(memoryMB)MB")
            throw ARError.processingFailed
        }
    }
    
    // MARK: - Environment Check
    public func checkEnvironment(with frame: ARFrame) throws {
        // Check lighting
        let lightEstimate = frame.lightEstimate?.ambientIntensity ?? 0
        guard lightEstimate >= 500 else { // 500 lux is minimum for good scanning
            logger.log(.error, message: "Insufficient lighting: \(lightEstimate) lux")
            throw ARError.insufficientLight
        }
        
        // Check motion
        let motion = frame.camera.eulerAngles.magnitude()
        guard motion < 0.5 else { // 0.5 radians per second maximum
            logger.log(.error, message: "Excessive motion detected: \(motion) rad/s")
            throw ARError.excessiveMotion
        }
    }
    
    // MARK: - Calibration Check
    public func checkCalibration(with frame: ARFrame) throws {
        guard frame.camera.intrinsics.determinant != 0 else {
            logger.log(.error, message: "Camera not calibrated")
            throw ARError.calibrationRequired
        }
    }
}

// MARK: - Helper Extensions
private extension simd_float3 {
    func magnitude() -> Float {
        sqrt(x * x + y * y + z * z)
    }
}
#else
public enum ARErrorHandler {
    public static func handle(_ error: Error) {
        print("AR features not available on this platform")
    }
}
#endif
