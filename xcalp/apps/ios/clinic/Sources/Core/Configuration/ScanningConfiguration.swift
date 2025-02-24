import Foundation

/// Configurations for scanning quality thresholds and parameters
public struct ScanningConfiguration {
    /// Quality thresholds for different scanning modes
    public struct QualityThresholds {
        /// Minimum quality score for LiDAR scanning (0-1)
        public static let minLidarQuality: Float = 0.7
        
        /// Minimum quality score for photogrammetry (0-1)
        public static let minPhotoQuality: Float = 0.6
        
        /// Minimum quality score for fusion mode (0-1)
        public static let fusionThreshold: Float = 0.8
        
        /// Required point density range (points/cm²)
        public static let minPointDensity: Float = 500
        public static let maxPointDensity: Float = 1000
        
        /// Surface completeness threshold (percentage)
        public static let surfaceCompleteness: Float = 0.98
        
        /// Maximum allowable noise level (mm)
        public static let maxNoiseLevel: Float = 0.1
        
        /// Feature preservation threshold (0-1)
        public static let featurePreservation: Float = 0.95
        
        /// Maximum fusion distance for point matching (mm)
        public static let maximumFusionDistance: Float = 0.5
    }
    
    /// Scanning mode transition parameters
    public struct TransitionParameters {
        /// Maximum number of fallback attempts
        public static let maxFallbackAttempts: Int = 3
        
        /// Base delay for exponential backoff (seconds)
        public static let baseBackoffDelay: TimeInterval = 1.0
        
        /// Maximum backoff delay (seconds)
        public static let maxBackoffDelay: TimeInterval = 8.0
    }
    
    /// Performance thresholds
    public struct PerformanceThresholds {
        /// Maximum processing time for scan (seconds)
        public static let maxProcessingTime: TimeInterval = 30.0
        
        /// Target frame rate for real-time processing
        public static let targetFrameRate: Int = 30
        
        /// Memory usage threshold (MB)
        public static let maxMemoryUsage: Int = 200
    }
    
    /// Clinical validation thresholds
    public struct ClinicalThresholds {
        /// Minimum measurement accuracy (mm)
        public static let measurementAccuracy: Float = 0.1
        
        /// Graft planning accuracy (percentage)
        public static let graftPlanningAccuracy: Float = 0.02
        
        /// Density mapping resolution (cm²)
        public static let densityMappingResolution: Float = 1.0
    }
}