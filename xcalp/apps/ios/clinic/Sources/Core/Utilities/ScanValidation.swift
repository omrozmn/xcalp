import ARKit
import CoreImage
import Foundation
import Metal
import os.log

class ScanValidation {
    enum ValidationError: Error {
        case insufficientPointCloud(found: Float, required: Float)
        case poorLighting(found: Float, required: Float)
        case excessiveMotion(found: Float, maximum: Float)
        case invalidDepthData(found: Float, required: Float)
        case unsupportedDevice
    }
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanValidation")
    private let sensorType: SensorCapabilityManager.ScannerType
    private let qualityAnalyzer: QualityAnalyzer
    
    init() {
        self.sensorType = SensorCapabilityManager.getScannerType()
        self.qualityAnalyzer = QualityAnalyzer()
    }
    
    static func validateScanQuality(_ scan: ARFrame) async throws {
        guard SensorCapabilityManager.isScanningSupported() else {
            throw ValidationError.unsupportedDevice
        }
        
        // Enhanced validation with Metal acceleration
        let quality = try await QualityAnalyzer.shared.analyzeFrame(scan)
        
        // Validate point cloud density with adaptive thresholds
        try await validatePointCloudDensity(scan, quality: quality)
        
        // Enhanced lighting validation
        try await validateLightingConditions(scan, quality: quality)
        
        // Improved motion validation with multi-frame analysis
        try await validateMotionStability(scan, quality: quality)
        
        // Validate depth quality with confidence mapping
        if let depthData = scan.sceneDepth {
            try await validateDepthQuality(depthData, sensorType: SensorCapabilityManager.getScannerType())
        }
    }
    
    private static func validatePointCloudDensity(_ frame: ARFrame, quality: QualityMetrics) async throws {
        let density = quality.pointCloudDensity
        let minDensity = getAdaptiveMinimumDensity(frame)
        
        guard density >= minDensity else {
            throw ValidationError.insufficientPointCloud(
                found: density,
                required: minDensity
            )
        }
    }
    
    private static func validateLightingConditions(_ frame: ARFrame, quality: QualityMetrics) async throws {
        let lightingQuality = quality.lightingQuality
        
        guard lightingQuality >= ClinicalConstants.minimumLightingQuality else {
            throw ValidationError.poorLighting(
                found: lightingQuality,
                required: ClinicalConstants.minimumLightingQuality
            )
        }
    }
    
    private static func validateMotionStability(_ frame: ARFrame, quality: QualityMetrics) async throws {
        let motionDeviation = quality.motionStability
        let threshold = getAdaptiveMotionThreshold(frame)
        
        guard motionDeviation <= threshold else {
            throw ValidationError.excessiveMotion(
                found: motionDeviation,
                maximum: threshold
            )
        }
    }
    
    private static func validateDepthQuality(_ depthData: ARDepthData, sensorType: SensorCapabilityManager.ScannerType) async throws {
        let confidence = try await QualityAnalyzer.shared.analyzeDepthConfidence(depthData)
        let minConfidence = getMinimumConfidence(for: sensorType)
        
        guard confidence >= minConfidence else {
            throw ValidationError.invalidDepthData(
                found: confidence,
                required: minConfidence
            )
        }
    }
    
    private static func getMinimumConfidence(for sensorType: SensorCapabilityManager.ScannerType) -> Float {
        switch sensorType {
        case .lidar:
            return ClinicalConstants.lidarMinimumDepthConfidence
        case .trueDepth:
            return ClinicalConstants.trueDepthMinimumDepthConfidence
        case .none:
            return 0.0
        }
    }
    
    private static func getAdaptiveMinimumDensity(_ frame: ARFrame) -> Float {
        let sensorType = SensorCapabilityManager.getScannerType()
        let baseThreshold = sensorType == .lidar ? 
            ClinicalConstants.lidarMinimumPointDensity : 
            ClinicalConstants.trueDepthMinimumPointDensity
        
        // Adjust based on lighting conditions
        if let lightEstimate = frame.lightEstimate {
            let lightingFactor = Float(lightEstimate.ambientIntensity) / 1000.0
            return baseThreshold * (0.7 + (0.3 * lightingFactor))
        }
        return baseThreshold
    }

    private static func getAdaptiveMotionThreshold(_ frame: ARFrame) -> Float {
        let baseThreshold = ClinicalConstants.maxMotionDeviation
        
        // Adjust based on tracking quality
        switch frame.camera.trackingState {
        case .normal:
            return baseThreshold
        case .limited:
            return baseThreshold * 1.5
        default:
            return baseThreshold * 0.8
        }
    }
}

// Error types with detailed information
extension ValidationError {
    struct QualityMetric {
        let found: Float
        let required: Float
    }
    
    enum ValidationError: LocalizedError {
        case unsupportedDevice
        case insufficientPointCloud(found: Float, required: Float)
        case poorLighting(found: Float, required: Float)
        case excessiveMotion(found: Float, maximum: Float)
        case invalidDepthData(found: Float, required: Float)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedDevice:
                return "Device does not support required scanning features"
            case .insufficientPointCloud(let found, let required):
                return "Insufficient point cloud density: \(found) points/cm² (required: \(required))"
            case .poorLighting(let found, let required):
                return "Poor lighting conditions: \(found)% (required: \(required)%)"
            case .excessiveMotion(let found, let maximum):
                return "Excessive motion detected: \(found) units (maximum: \(maximum))"
            case .invalidDepthData(let found, let required):
                return "Invalid depth data: \(found)% confidence (required: \(required)%)"
            }
        }
    }
}
