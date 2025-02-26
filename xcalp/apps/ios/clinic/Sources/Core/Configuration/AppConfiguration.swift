import Foundation
import Metal

public enum AppConfiguration {
    public struct Performance {
        public struct Thresholds {
            public static let maxMemoryUsage: UInt64 = 200 * 1024 * 1024  // 200MB
            public static let minFrameRate: Double = 30.0
            public static let maxProcessingTime: TimeInterval = 5.0
            public static let maxGPUUtilization: Double = 0.85 // 85%
            public static let maxCPUUsage: Double = 0.80 // 80%
        }
        
        public struct Scanning {
            public static let minPointDensity: Float = 750 // points/cm²
            public static let minSurfaceCompleteness: Float = 0.985 // 98.5%
            public static let maxNoiseLevel: Float = 0.08 // mm
            public static let minFeaturePreservation: Float = 0.97 // 97%
        }
        
        public struct Quality {
            public static let meshVertexLimit = 10000
            public static let optimizationInterval: TimeInterval = 2.0
            public static let qualityCheckInterval: TimeInterval = 1.0
        }
    }
    
    public struct Metal {
        public enum FloatingPointPrecision {
            case full
            case half
            case reduced
        }
        
        public enum PowerMode {
            case balanced
            case performance
            case efficiency
            case minimum
        }
    }
    
    public struct Security {
        public static let keyRotationInterval: TimeInterval = 7776000 // 90 days
        public static let sessionTimeout: TimeInterval = 1800 // 30 minutes
        public static let maxLoginAttempts = 5
        public static let minPasswordLength = 12
    }
    
    public struct Networking {
        public static let timeoutInterval: TimeInterval = 30
        public static let maxRetryAttempts = 3
        public static let retryDelay: TimeInterval = 1.0
        public static let maxConcurrentOperations = 4
    }
    
    public struct Cache {
        public static let maxAge: TimeInterval = 3600 // 1 hour
        public static let maxSize: Int = 100 * 1024 * 1024 // 100MB
    }
    
    public enum Performance {
        public enum Scanning {
            public static let minPointDensity: Float = 100.0 // points per square cm
            public static let minSurfaceCompleteness: Double = 0.85 // 85% coverage
            public static let maxNoiseLevel: Float = 0.02 // 2% noise tolerance
            public static let minFeaturePreservation: Float = 0.9 // 90% feature preservation
            public static let minLightIntensity: Float = 0.6 // 60% minimum lighting
            public static let maxScanDuration: TimeInterval = 300 // 5 minutes
            public static let maxFileSize: UInt64 = 100_000_000 // 100MB
        }
        
        public enum Thresholds {
            public static let maxCPUUsage: Double = 0.8 // 80%
            public static let maxMemoryUsage: UInt64 = 2_000_000_000 // 2GB
            public static let maxGPUUtilization: Double = 0.9 // 90%
            public static let minFrameRate: Double = 30.0 // fps
            public static let thermalThreshold: Int = 3 // Serious thermal state
            public static let maxDiskUsage: Double = 0.9 // 90%
        }
        
        public enum Cache {
            public static let maxCacheSize: UInt64 = 500_000_000 // 500MB
            public static let maxCacheAge: TimeInterval = 86400 // 24 hours
            public static let cleanupThreshold: Double = 0.8 // 80%
            public static let compressionLevel: Float = 0.7 // 70%
        }
        
        public enum Processing {
            public static let maxBatchSize: Int = 32
            public static let maxThreads: Int = 4
            public static let timeoutInterval: TimeInterval = 30 // 30 seconds
            public static let retryAttempts: Int = 3
            public static let maxQueueSize: Int = 100
        }
    }
    
    public enum Quality {
        public enum Resolution {
            case low(width: Int = 1024, height: Int = 1024)
            case medium(width: Int = 2048, height: Int = 2048)
            case high(width: Int = 4096, height: Int = 4096)
            
            public var dimensions: (width: Int, height: Int) {
                switch self {
                case .low(let w, let h): return (w, h)
                case .medium(let w, let h): return (w, h)
                case .high(let w, let h): return (w, h)
                }
            }
        }
        
        public enum Compression {
            case lossless
            case high
            case medium
            case low
            
            public var compressionFactor: Float {
                switch self {
                case .lossless: return 1.0
                case .high: return 0.8
                case .medium: return 0.6
                case .low: return 0.4
                }
            }
        }
        
        public enum Detail {
            case minimal
            case standard
            case enhanced
            case maximum
            
            public var vertexDensity: Float {
                switch self {
                case .minimal: return 50.0
                case .standard: return 100.0
                case .enhanced: return 200.0
                case .maximum: return 400.0
                }
            }
        }
    }
    
    public enum Security {
        public static let encryptionEnabled = true
        public static let minimumKeyLength = 256
        public static let hashAlgorithm = "SHA256"
        public static let maxFailedAttempts = 3
        public static let sessionTimeout: TimeInterval = 1800 // 30 minutes
    }
    
    public enum Network {
        public static let timeoutInterval: TimeInterval = 30
        public static let maxRetries = 3
        public static let retryDelay: TimeInterval = 5
        public static let maxConcurrentOperations = 4
        public static let compressionEnabled = true
        
        public enum Uploads {
            public static let chunkSize: Int = 1_024_000 // 1MB
            public static let maxFileSize: Int64 = 1_000_000_000 // 1GB
            public static let allowedTypes = ["usdz", "obj", "ply"]
        }
    }
    
    public enum Storage {
        public static let maxLocalStorage: UInt64 = 10_000_000_000 // 10GB
        public static let autoCleanupEnabled = true
        public static let cleanupThreshold: Double = 0.9 // 90%
        public static let minFreeSpace: UInt64 = 1_000_000_000 // 1GB
        
        public enum Cache {
            public static let maxSize: UInt64 = 1_000_000_000 // 1GB
            public static let expirationInterval: TimeInterval = 604800 // 1 week
        }
    }
    
    public enum UI {
        public static let animationDuration: TimeInterval = 0.3
        public static let hapticFeedbackEnabled = true
        public static let maxFPS = 60
        public static let previewResolution = Quality.Resolution.medium()
        
        public enum Colors {
            public static let primaryHex = "#007AFF"
            public static let secondaryHex = "#5856D6"
            public static let accentHex = "#FF2D55"
            public static let warningHex = "#FF9500"
            public static let errorHex = "#FF3B30"
        }
    }
    
    public enum Debug {
        public static let loggingEnabled = true
        public static let performanceMetricsEnabled = true
        public static let meshWireframeEnabled = false
        public static let showFPS = true
        public static let showMemoryUsage = true
        
        public enum Logging {
            public static let maxLogSize: UInt64 = 10_000_000 // 10MB
            public static let maxLogAge: TimeInterval = 604800 // 1 week
            public static let logLevel: String = "debug"
        }
    }
}

// MARK: - Supporting Types

public enum ScanningMode: String {
    case lidar = "LiDAR"
    case photogrammetry = "Photogrammetry"
    case hybrid = "Hybrid"
}

public struct ScanningConfiguration {
    public let mode: ScanningMode
    public let resolution: AppConfiguration.Quality.Resolution
    public let compression: AppConfiguration.Quality.Compression
    public let detail: AppConfiguration.Quality.Detail
    
    public init(
        mode: ScanningMode = .hybrid,
        resolution: AppConfiguration.Quality.Resolution = .medium(),
        compression: AppConfiguration.Quality.Compression = .high,
        detail: AppConfiguration.Quality.Detail = .standard
    ) {
        self.mode = mode
        self.resolution = resolution
        self.compression = compression
        self.detail = detail
    }
}