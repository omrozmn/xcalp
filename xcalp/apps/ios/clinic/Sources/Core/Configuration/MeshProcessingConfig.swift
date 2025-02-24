import Foundation
import Metal

struct MeshProcessingConfig {
    let quality: ProcessingQuality
    let gpuAcceleration: GPUAccelerationMode
    let optimizationProfile: OptimizationProfile
    let featurePreservation: FeaturePreservationSettings
    let memoryManagement: MemoryManagementSettings
    
    static var `default`: MeshProcessingConfig {
        MeshProcessingConfig(
            quality: .balanced,
            gpuAcceleration: .automatic,
            optimizationProfile: .balanced,
            featurePreservation: .init(),
            memoryManagement: .init()
        )
    }
    
    static func optimize(for device: MTLDevice?) -> MeshProcessingConfig {
        let gpuMode: GPUAccelerationMode = device?.supportsFamily(.apple3) == true ? .preferred : .disabled
        let quality: ProcessingQuality = device?.supportsFamily(.apple4) == true ? .high : .balanced
        
        return MeshProcessingConfig(
            quality: quality,
            gpuAcceleration: gpuMode,
            optimizationProfile: .performance,
            featurePreservation: .init(adaptiveThreshold: true),
            memoryManagement: .init(aggressiveOptimization: true)
        )
    }
}

enum ProcessingQuality {
    case draft
    case balanced
    case high
    
    var poissonDepth: Int {
        switch self {
        case .draft: return 6
        case .balanced: return 8
        case .high: return 10
        }
    }
    
    var minimumPointCount: Int {
        switch self {
        case .draft: return 1000
        case .balanced: return 5000
        case .high: return 10000
        }
    }
    
    var smoothingIterations: Int {
        switch self {
        case .draft: return 1
        case .balanced: return 2
        case .high: return 3
        }
    }
}

enum GPUAccelerationMode {
    case disabled
    case automatic
    case preferred
    case required
    
    var shouldUseGPU: Bool {
        switch self {
        case .disabled: return false
        case .automatic: return MTLCreateSystemDefaultDevice() != nil
        case .preferred, .required: return true
        }
    }
}

enum OptimizationProfile {
    case quality
    case balanced
    case performance
    
    var meshSimplificationRatio: Float {
        switch self {
        case .quality: return 0.9
        case .balanced: return 0.7
        case .performance: return 0.5
        }
    }
    
    var maxParallelOperations: Int {
        switch self {
        case .quality: return 2
        case .balanced: return 4
        case .performance: return 8
        }
    }
}

struct FeaturePreservationSettings {
    var featureAngleThreshold: Float = 30.0 // degrees
    var adaptiveThreshold: Bool = false
    var preservationWeight: Float = 0.8
    var minFeatureSize: Float = 0.001 // meters
    
    init(
        featureAngleThreshold: Float = 30.0,
        adaptiveThreshold: Bool = false,
        preservationWeight: Float = 0.8,
        minFeatureSize: Float = 0.001
    ) {
        self.featureAngleThreshold = featureAngleThreshold
        self.adaptiveThreshold = adaptiveThreshold
        self.preservationWeight = preservationWeight
        self.minFeatureSize = minFeatureSize
    }
}

struct MemoryManagementSettings {
    var maxMemoryUsage: UInt64 = 512 * 1024 * 1024 // 512MB
    var aggressiveOptimization: Bool = false
    var useMemoryMapping: Bool = true
    var chunkSize: Int = 1024 * 1024 // 1MB chunks
    
    init(
        maxMemoryUsage: UInt64 = 512 * 1024 * 1024,
        aggressiveOptimization: Bool = false,
        useMemoryMapping: Bool = true,
        chunkSize: Int = 1024 * 1024
    ) {
        self.maxMemoryUsage = maxMemoryUsage
        self.aggressiveOptimization = aggressiveOptimization
        self.useMemoryMapping = useMemoryMapping
        self.chunkSize = chunkSize
    }
}