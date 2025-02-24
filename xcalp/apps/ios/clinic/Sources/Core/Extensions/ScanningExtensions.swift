import ARKit
import simd

// MARK: - Geometry Extensions
extension simd_float4x4 {
    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let homogeneous = simd_float4(point.x, point.y, point.z, 1)
        let transformed = self * homogeneous
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z) / transformed.w
    }
    
    func transformDirection(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let homogeneous = simd_float4(direction.x, direction.y, direction.z, 0)
        let transformed = self * homogeneous
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }
}

extension ARMeshGeometry {
    subscript(index: Int) -> SIMD3<Float> {
        vertices[index]
    }
    
    func hasValidTexture(forFaceIndex index: Int) -> Bool {
        guard let textureCoordinates = textureCoordinates else {
            return false
        }
        
        let indices = [
            faces[index],
            faces[index + 1],
            faces[index + 2]
        ]
        
        return indices.allSatisfy { i in
            let uv = textureCoordinates[Int(i)]
            return uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1
        }
    }
}

extension ARGeometrySource {
    subscript(index: Int) -> SIMD3<Float> {
        let stride = self.stride
        let elementSize = MemoryLayout<Float>.size
        let baseAddress = buffer.contents().advanced(by: self.offset)
        
        let x = baseAddress.advanced(by: index * stride).assumingMemoryBound(to: Float.self).pointee
        let y = baseAddress.advanced(by: index * stride + elementSize).assumingMemoryBound(to: Float.self).pointee
        let z = baseAddress.advanced(by: index * stride + 2 * elementSize).assumingMemoryBound(to: Float.self).pointee
        
        return SIMD3<Float>(x, y, z)
    }
}

// MARK: - Error Handling
protocol ScanningError: LocalizedError {
    var recoveryOptions: [String] { get }
    var severity: ErrorSeverity { get }
}

enum ErrorSeverity: Int {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
}

extension ARError: ScanningError {
    var recoveryOptions: [String] {
        switch code {
        case .sensorUnavailable, .sensorFailed:
            return [
                "Ensure device has sufficient battery",
                "Check for system updates",
                "Restart device"
            ]
        case .worldTrackingFailed:
            return [
                "Move to a well-lit area",
                "Ensure sufficient visual features in environment",
                "Move device more slowly"
            ]
        default:
            return ["Restart scanning session"]
        }
    }
    
    var severity: ErrorSeverity {
        switch code {
        case .sensorUnavailable, .sensorFailed:
            return .critical
        case .worldTrackingFailed:
            return .high
        default:
            return .medium
        }
    }
}

// MARK: - Quality Protocols
protocol QualityMetric {
    var score: Float { get }
    var weight: Float { get }
    var threshold: Float { get }
    var isPassing: Bool { get }
}

extension QualityMetric {
    var isPassing: Bool {
        score >= threshold
    }
}

struct GeometricQuality: QualityMetric {
    let score: Float
    let weight: Float = 0.4
    let threshold: Float = AppConfig.minimumMeshConfidence
}

struct TextureQuality: QualityMetric {
    let score: Float
    let weight: Float = 0.3
    let threshold: Float = AppConfig.minimumPhotogrammetryConfidence
}

struct FeatureQuality: QualityMetric {
    let score: Float
    let weight: Float = 0.3
    let threshold: Float = AppConfig.minFeatureMatchConfidence
}

// MARK: - Logging Support
extension PerformanceMonitor {
    static func logScanningMetrics(
        lidarQuality: Float,
        photoQuality: Float,
        fusionQuality: Float?,
        processingTime: TimeInterval
    ) {
        let metrics = [
            "lidar_quality": lidarQuality,
            "photo_quality": photoQuality,
            "fusion_quality": fusionQuality as Any,
            "processing_time": processingTime
        ]
        
        AnalyticsService.shared.logEvent(
            "scan_quality_metrics",
            parameters: metrics as [String: Any]
        )
    }
}

// MARK: - Configuration Support
protocol ScanningConfiguration {
    var resolution: Float { get }
    var accuracy: Float { get }
    var featureThreshold: Float { get }
}

struct LidarConfiguration: ScanningConfiguration {
    let resolution: Float = 0.005 // 5mm resolution
    let accuracy: Float = 0.99
    let featureThreshold: Float = AppConfig.lidarConfidenceThreshold
}

struct PhotogrammetryConfiguration: ScanningConfiguration {
    let resolution: Float = 0.002 // 2mm resolution
    let accuracy: Float = 0.95
    let featureThreshold: Float = AppConfig.minimumPhotogrammetryConfidence
}

struct HybridConfiguration: ScanningConfiguration {
    let resolution: Float = 0.001 // 1mm resolution
    let accuracy: Float = 0.98
    let featureThreshold: Float = AppConfig.minimumFusionQuality
}
