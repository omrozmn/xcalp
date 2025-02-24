import Foundation

/// Configuration constants for the clinic application
struct AppConfig {
    // MARK: - General Configuration
    
    /// Application version
    static let appVersion: String = "1.0.0"
    
    /// Build number
    static let buildNumber: String = "1"
    
    // MARK: - Mesh Processing Configuration
    
    /// Minimum point density for general mesh validation (points/cm²)
    static let minimumPointDensity: Float = 200.0
    
    /// Feature preservation threshold (0-1)
    static let featurePreservationThreshold: Float = 0.85
    
    /// Minimum mesh resolution in millimeters
    static let meshResolutionMin: Float = 0.1
    
    /// Maximum mesh resolution in millimeters
    static let meshResolutionMax: Float = 0.5
    
    /// Number of Laplacian smoothing iterations
    static let smoothingIterations: Int = 3
    
    // MARK: - LiDAR Configuration
    
    /// Minimum point density for LiDAR scanning (points/cm²)
    static let lidarMinimumPointDensity: Float = 500.0
    
    /// Maximum depth for LiDAR-based Poisson reconstruction
    static let lidarPoissonDepth: Int = 12
    
    // MARK: - TrueDepth Configuration
    
    /// Minimum point density for TrueDepth scanning (points/cm²)
    static let trueDepthMinimumPointDensity: Float = 300.0
    
    /// Maximum depth for TrueDepth-based Poisson reconstruction
    static let trueDepthPoissonDepth: Int = 10
    
    // MARK: - Photogrammetry Configuration
    
    /// Minimum number of features for photogrammetry
    static let minPhotogrammetryFeatures: Int = 100
    
    /// Minimum confidence score for feature detection
    static let minimumFeatureConfidence: Float = 0.7
    
    /// Minimum quality score for mesh fusion
    static let minimumFusionQuality: Float = 0.8
    
    // MARK: - Poisson Reconstruction Parameters
    
    /// Default Poisson reconstruction depth
    static let defaultPoissonDepth: Int = 8
    
    /// Poisson samples per node
    static let poissonSamplesPerNode: Int = 1
    
    /// Poisson point weight
    static let poissonPointWeight: Float = 4.0
    
    // MARK: - Quality Metrics
    
    /// Minimum vertex density
    static let minimumVertexDensity: Float = 10.0
    
    /// Minimum normal consistency
    static let minimumNormalConsistency: Float = 0.8
    
    /// Minimum surface smoothness
    static let minimumSurfaceSmoothness: Float = 0.7
    
    /// Minimum mesh triangulation quality score (0-1)
    static let meshTriangulationQuality: Float = 0.7
    
    // MARK: - Clinical Guidelines
    
    /// Minimum scan lighting in lux
    static let minimumScanLightingLux: Float = 100.0
    
    /// Maximum motion deviation between frames
    static let maximumMotionDeviation: Float = 0.02
    
    /// Graft calculation precision
    static let graftCalculationPrecision: Float = 0.01
    
    /// Area measurement precision
    static let areaMeasurementPrecision: Float = 0.3
    
    /// Density mapping resolution
    static let densityMappingResolution: Float = 0.5
    
    // MARK: - Validation Requirements
    
    /// Minimum scan quality score
    static let minimumScanQualityScore: Float = 0.85
    
    /// Minimum processing success rate
    static let minimumProcessingSuccess: Float = 0.95
    
    // MARK: - Fusion Parameters
    
    /// Minimum fusion quality
    static let minimumFusionQualityScore: Float = 0.75
    
    /// Minimum feature match confidence
    static let minFeatureMatchConfidence: Float = 0.8
    
    /// Maximum reprojection error
    static let maxReprojectionError: Float = 0.005
    
    /// Minimum inlier ratio
    static let minInlierRatio: Float = 0.6
    
    // MARK: - Performance Thresholds
    
    /// Maximum uncompressed mesh size
    static let maxUncompressedMeshSize: Int = 100 * 1024 * 1024
    
    /// Maximum processing time in seconds
    static let maxProcessingTime: TimeInterval = 30.0
    
    // MARK: - Bundle Adjustment Parameters
    
    /// Maximum bundle adjustment iterations
    static let bundleAdjustmentMaxIterations: Int = 100
    
    /// Bundle adjustment convergence threshold
    static let bundleAdjustmentConvergenceThreshold: Float = 1e-6
    
    // MARK: - ICP Parameters
    
    /// Maximum ICP iterations
    static let icpMaxIterations: Int = 50
    
    /// ICP convergence threshold
    static let icpConvergenceThreshold: Float = 1e-6
    
    /// Maximum correspondence distance
    static let maxCorrespondenceDistance: Float = 0.01
}
