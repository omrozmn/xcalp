import Foundation
import Metal

public struct ScanData: Codable {
    public let id: UUID
    public let timestamp: Date
    public let meshData: ProcessedMeshData
    public let settings: ScanSettings
    public let deviceInfo: DeviceInfo
    public let environmentInfo: EnvironmentInfo
    
    public init(
        mesh: MeshProcessor.ProcessedMesh,
        settings: ScanSettings,
        deviceInfo: DeviceInfo,
        environmentInfo: EnvironmentInfo
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.meshData = ProcessedMeshData(from: mesh)
        self.settings = settings
        self.deviceInfo = deviceInfo
        self.environmentInfo = environmentInfo
    }
}

// MARK: - Supporting Types
public struct ProcessedMeshData: Codable {
    public let vertices: [SIMD3<Float>]
    public let indices: [UInt32]
    public let normals: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    public let quality: MeshQualityData
    public let metrics: ProcessingMetricsData
    
    init(from mesh: MeshProcessor.ProcessedMesh) {
        // Convert Metal buffers to arrays for serialization
        self.vertices = mesh.vertices.contents().assumingMemoryBound(to: SIMD3<Float>.self).map { $0 }
        self.indices = mesh.indices.contents().assumingMemoryBound(to: UInt32.self).map { $0 }
        self.normals = mesh.normals.contents().assumingMemoryBound(to: SIMD3<Float>.self).map { $0 }
        self.uvs = mesh.uvs.contents().assumingMemoryBound(to: SIMD2<Float>.self).map { $0 }
        self.quality = MeshQualityData(from: mesh.quality)
        self.metrics = ProcessingMetricsData(from: mesh.metrics)
    }
}

public struct MeshQualityData: Codable {
    public let vertexDensity: Float
    public let surfaceSmoothness: Float
    public let normalConsistency: Float
    public let holes: [HoleInfo]
    
    public struct HoleInfo: Codable {
        public let center: SIMD3<Float>
        public let radius: Float
    }
    
    init(from quality: MeshProcessor.MeshQuality) {
        self.vertexDensity = quality.vertexDensity
        self.surfaceSmoothness = quality.surfaceSmoothness
        self.normalConsistency = quality.normalConsistency
        self.holes = quality.holes.map { HoleInfo(center: $0.center, radius: $0.radius) }
    }
}

public struct ProcessingMetricsData: Codable {
    public let originalVertexCount: Int
    public let optimizedVertexCount: Int
    public let processingTime: TimeInterval
    public let memoryUsage: Int64
    
    init(from metrics: MeshProcessor.ProcessingMetrics) {
        self.originalVertexCount = metrics.originalVertexCount
        self.optimizedVertexCount = metrics.optimizedVertexCount
        self.processingTime = metrics.processingTime
        self.memoryUsage = metrics.memoryUsage
    }
}

// MARK: - Default Values
extension ScanSettings {
    static var `default`: ScanSettings {
        ScanSettings(
            resolution: .high,
            accuracy: .balanced,
            filteringOptions: .init(
                smoothing: true,
                removeOutliers: true,
                fillHoles: true
            )
        )
    }
}

extension DeviceInfo {
    static var current: DeviceInfo {
        DeviceInfo(
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            lidarCapabilities: .current
        )
    }
}

extension LidarCapabilities {
    static var current: LidarCapabilities {
        LidarCapabilities(
            hasSceneReconstruction: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            hasPersonSegmentation: ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth),
            maxMeshResolution: 100_000 // Default maximum vertices
        )
    }
}

extension EnvironmentInfo {
    static var current: EnvironmentInfo {
        // TODO: Implement environment detection using ARKit
        EnvironmentInfo(
            lightingCondition: .moderate,
            roomSize: .medium,
            surfaceComplexity: .moderate
        )
    }
}
