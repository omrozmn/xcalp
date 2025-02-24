import Foundation

/// Clinical constants based on international standards and guidelines
/// References:
/// - ISHRS: International Society of Hair Restoration Surgery
/// - ASPS: American Society of Plastic Surgeons
/// - IAAPS: International Association of Aesthetic Plastic Surgery
/// - MDPI Research Guidelines
public enum ClinicalConstants {
    // MARK: - Quality Thresholds
    
    /// Minimum point density for LiDAR scanning (points/cm²)
    static let lidarMinimumPointDensity: Float = 500.0
    
    /// Minimum point density for TrueDepth scanning (points/cm²)
    static let trueDepthMinimumPointDensity: Float = 300.0
    
    /// Minimum point density for general mesh validation (points/cm²)
    static let minimumPointDensity: Float = 200.0
    
    /// Minimum confidence score for normal vectors (0-1)
    static let minimumNormalConsistency: Float = 0.85
    
    /// Minimum surface smoothness score (0-1)
    static let minimumSurfaceSmoothness: Float = 0.75
    
    /// Minimum feature preservation score (0-1)
    static let featurePreservationThreshold: Float = 0.8
    
    /// Minimum mesh triangulation quality score (0-1)
    static let meshTriangulationQuality: Float = 0.7
    
    // MARK: - Processing Parameters
    
    /// Maximum depth for LiDAR-based Poisson reconstruction
    static let lidarPoissonDepth: Int = 12
    
    /// Maximum depth for TrueDepth-based Poisson reconstruction
    static let trueDepthPoissonDepth: Int = 10
    
    /// Default Poisson reconstruction depth
    static let defaultPoissonDepth: Int = 8
    
    /// Number of Laplacian smoothing iterations
    static let laplacianIterations: Int = 3
    
    /// Minimum mesh resolution in millimeters
    static let meshResolutionMin: Float = 0.5
    
    // MARK: - Photogrammetry
    
    /// Minimum number of features for photogrammetry
    static let minPhotogrammetryFeatures: Int = 100
    
    /// Minimum confidence score for feature detection
    static let minimumFeatureConfidence: Float = 0.7
    
    /// Minimum quality score for mesh fusion
    static let minimumFusionQuality: Float = 0.8
}
