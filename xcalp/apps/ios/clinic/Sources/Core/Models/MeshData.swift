import Foundation
import simd
import Metal

/// Core data structure representing a 3D mesh with quality metrics
struct MeshData {
    /// Vertex positions in 3D space
    let vertices: [SIMD3<Float>]
    
    /// Triangle indices defining mesh topology
    let indices: [UInt32]
    
    /// Vertex normals for lighting and analysis
    let normals: [SIMD3<Float>]
    
    /// Confidence values per vertex (0-1)
    let confidence: [Float]
    
    /// Mesh metadata and statistics
    var metadata: MeshMetadata
    
    /// Quality metrics for the mesh
    var qualityMetrics: QualityMetrics?
    
    init(
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        normals: [SIMD3<Float>],
        confidence: [Float],
        metadata: MeshMetadata = MeshMetadata(),
        qualityMetrics: QualityMetrics? = nil
    ) {
        self.vertices = vertices
        self.indices = indices
        self.normals = normals
        self.confidence = confidence
        self.metadata = metadata
        self.qualityMetrics = qualityMetrics
    }
}

/// Additional metadata for mesh processing and tracking
struct MeshMetadata: Codable {
    /// Timestamp when mesh was created/processed
    let timestamp: Date
    
    /// Source of mesh data (LiDAR, Photogrammetry, etc)
    let source: MeshSource
    
    /// Processing history for tracking changes
    var processingSteps: [ProcessingStep]
    
    /// Spatial bounds of the mesh
    var boundingBox: BoundingBox
    
    init(
        timestamp: Date = Date(),
        source: MeshSource = .lidar,
        processingSteps: [ProcessingStep] = [],
        boundingBox: BoundingBox = BoundingBox()
    ) {
        self.timestamp = timestamp
        self.source = source
        self.processingSteps = processingSteps
        self.boundingBox = boundingBox
    }
}

/// Defines the source/type of mesh data
enum MeshSource: String, Codable {
    case lidar
    case photogrammetry
    case fusion
    case reconstruction
}

/// Tracks individual processing operations on mesh
struct ProcessingStep: Codable {
    let operation: String
    let timestamp: Date
    let parameters: [String: String]
    let qualityImpact: Float?
}

/// Geometric bounds of mesh in 3D space
struct BoundingBox: Codable {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    
    init(min: SIMD3<Float> = .init(repeating: .infinity),
         max: SIMD3<Float> = .init(repeating: -.infinity)) {
        self.min = min
        self.max = max
    }
    
    mutating func union(with point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }
    
    var center: SIMD3<Float> {
        return (min + max) * 0.5
    }
    
    var size: SIMD3<Float> {
        return max - min
    }
}

/// Quality metrics for mesh evaluation
struct QualityMetrics: Codable {
    /// Points per cubic meter
    let pointDensity: Float
    
    /// Percentage of surface covered (0-1)
    let surfaceCompleteness: Float
    
    /// Average deviation from expected surface (meters)
    let noiseLevel: Float
    
    /// Preservation of geometric features (0-1)
    let featurePreservation: Float
    
    /// Overall quality score (0-1)
    var averageQuality: Float {
        return (
            normalizedDensity +
            surfaceCompleteness +
            (1.0 - noiseLevel) +
            featurePreservation
        ) / 4.0
    }
    
    private var normalizedDensity: Float {
        return min(pointDensity / 1000.0, 1.0)
    }
    
    var isAcceptable: Bool {
        return surfaceCompleteness >= 0.85 &&
               pointDensity >= 100.0 &&
               noiseLevel <= 0.1 &&
               featurePreservation >= 0.8
    }
}