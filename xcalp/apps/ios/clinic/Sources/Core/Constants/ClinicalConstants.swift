import Foundation

struct ClinicalConstants {
    // Mesh Processing Constants (Based on Kazhdan & Sorkine research)
    static let meshResolutionMin: Float = 0.001  // 1mm minimum detail
    static let meshResolutionMax: Float = 0.01   // 1cm maximum detail
    static let poissonSamplesPerNode: Int = 1
    static let poissonPointWeight: Float = 4.0
    static let laplacianIterations: Int = 3
    static let featurePreservationThreshold: Float = 0.1

    // Sensor-specific Point Cloud Requirements (Based on MDPI research)
    static let lidarMinimumPointDensity: Float = 1000.0  // points per cubic meter
    static let trueDepthMinimumPointDensity: Float = 500.0  // points per cubic meter
    static let minimumPointDensity: Float = 100.0
    
    // Poisson Reconstruction Parameters
    static let lidarPoissonDepth: Int = 10
    static let trueDepthPoissonDepth: Int = 8
    static let defaultPoissonDepth: Int = 8
    
    // Minimum Points Per Node
    static let lidarMinPointsPerNode: Int = 8
    static let trueDepthMinPointsPerNode: Int = 12
    static let defaultMinPointsPerNode: Int = 10

    // Quality Metrics (Based on Wiley research)
    static let minimumVertexDensity: Float = 10.0
    static let minimumNormalConsistency: Float = 0.8
    static let minimumSurfaceSmoothness: Float = 0.7

    // Clinical Guidelines (Based on ISHRS & IAAPS)
    static let minimumScanLightingLux: Float = 100.0
    static let maximumMotionDeviation: Float = 0.02  // Maximum motion between frames
    static let graftCalculationPrecision: Float = 0.01 // ±1% (Improved precision)
    static let areaMeasurementPrecision: Float = 0.3 // mm (Improved precision)
    static let densityMappingResolution: Float = 0.5 // cm² (Higher resolution mapping)
    
    // Validation Requirements
    static let minimumScanQualityScore: Float = 0.85
    static let minimumProcessingSuccess: Float = 0.95

    // New constants from latest research papers
    static let minimumFusionQuality: Float = 0.75
    static let photogrammetryMinFeatures: Int = 100 // Minimum features for reliable reconstruction
    static let meshTriangulationQuality: Float = 0.6
    static let surfaceConsistencyThreshold: Float = 0.93 // From MDPI paper
    
    // Updated clinical accuracy requirements
    static let graftPlanningPrecision: Float = 0.98 // ±2% as per ISHRS
    static let densityMappingAccuracy: Float = 0.99 // Based on latest IAAPS guidelines
    static let featureDetectionConfidence: Float = 0.95 // From computer vision research
    
    // Photogrammetry fusion parameters
    static let minFeatureMatchConfidence: Float = 0.8
    static let maxReprojectionError: Float = 0.005 // pixels
    static let minInlierRatio: Float = 0.6

    // Performance thresholds
    static let maxUncompressedMeshSize: Int = 100 * 1024 * 1024  // 100MB
    static let maxProcessingTime: TimeInterval = 30.0  // Maximum processing time in seconds
    
    // Bundle adjustment parameters
    static let bundleAdjustmentMaxIterations: Int = 100
    static let bundleAdjustmentConvergenceThreshold: Float = 1e-6
    
    // ICP parameters
    static let icpMaxIterations: Int = 50
    static let icpConvergenceThreshold: Float = 1e-6
    static let maxCorrespondenceDistance: Float = 0.01  // 1cm maximum correspondence distance
}

public enum ClinicalConstants {
    // Point cloud density requirements (points per cubic meter)
    public static let optimalPointDensity: Float = 1000.0
    public static let minimumPointDensity: Float = 500.0
    
    // Mesh quality thresholds
    public static let minimumMeshConfidence: Float = 0.7
    public static let minimumSurfaceNormalConsistency: Float = 0.8
    public static let maximumDepthDiscontinuity: Float = 0.1 // meters
    
    // Feature detection
    public static let minFeatureMatchConfidence: Float = 0.7
    public static let photogrammetryMinFeatures: Int = 100
    public static let maxReprojectionError: Float = 0.01
    public static let minInlierRatio: Float = 0.6
    
    // Fusion requirements
    public static let minimumFusionQuality: Float = 0.75
    public static let minimumPhotogrammetryConfidence: Float = 0.6
    
    // Clinical accuracy requirements
    public static let graftPlanningPrecision: Float = 0.98
    public static let featurePreservationThreshold: Float = 0.95
    
    // LiDAR specific
    public static let lidarMinimumPointDensity: Float = 800.0
    public static let lidarConfidenceThreshold: Float = 0.7
    
    // TrueDepth specific
    public static let trueDepthMinimumPointDensity: Float = 400.0
    public static let trueDepthConfidenceThreshold: Float = 0.6
}

enum ScanningQualityThresholds {
    // LiDAR quality thresholds
    static let minimumLidarPoints: Int = 1000
    static let minimumLidarConfidence: Float = 0.7
    static let optimumLidarPointDensity: Float = 100.0 // points per square cm
    
    // Photogrammetry quality thresholds
    static let minimumPhotogrammetryPoints: Int = 2000
    static let minimumFeatureMatches: Int = 100
    static let minimumPhotogrammetryConfidence: Float = 0.6
    
    // Fusion parameters
    static let maximumFusionDistance: Float = 0.5 // cm
    static let minimumOverlapPercentage: Float = 30.0
    static let fusionConfidenceThreshold: Float = 0.8
}

enum FallbackTriggers {
    // LiDAR fallback conditions
    static let insufficientLidarPoints = "INSUFFICIENT_LIDAR_POINTS"
    static let lowLidarConfidence = "LOW_LIDAR_CONFIDENCE"
    static let inconsistentDepthData = "INCONSISTENT_DEPTH_DATA"
    
    // Photogrammetry fallback conditions
    static let insufficientFeatures = "INSUFFICIENT_FEATURES"
    static let poorImageQuality = "POOR_IMAGE_QUALITY"
    static let inadequateOverlap = "INADEQUATE_OVERLAP"
    
    // Fusion triggers
    static let complementaryData = "COMPLEMENTARY_DATA_AVAILABLE"
    static let highConfidenceOverlap = "HIGH_CONFIDENCE_OVERLAP"
    static let consistentGeometry = "CONSISTENT_GEOMETRY"
}

enum ScanningModes: String {
    case lidarOnly = "LIDAR_ONLY"
    case photogrammetryOnly = "PHOTOGRAMMETRY_ONLY"
    case hybridFusion = "HYBRID_FUSION"
    
    var fallbackMode: ScanningModes {
        switch self {
        case .lidarOnly:
            return .photogrammetryOnly
        case .photogrammetryOnly:
            return .lidarOnly
        case .hybridFusion:
            return .lidarOnly
        }
    }
}
