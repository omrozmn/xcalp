import ARKit
import Metal
import CoreML
import MetalKit

public class DeviceCapabilityDetector {
    public static let shared = DeviceCapabilityDetector()
    
    private var metalDevice: MTLDevice?
    private var arConfiguration: ARWorldTrackingConfiguration?
    
    public struct DeviceCapabilities {
        public let hasLiDAR: Bool
        public let supportsMeshAnchors: Bool
        public let supportsSceneReconstruction: Bool
        public let maxTextureSize: Int
        public let supportsMSAA: Bool
        public let supportsRayTracing: Bool
        public let maxThreadgroupSize: Int
        public let thermalThrottlingSupported: Bool
        public let gpuFamily: String
        public let memoryBudget: UInt64
    }
    
    private init() {
        metalDevice = MTLCreateSystemDefaultDevice()
        arConfiguration = ARWorldTrackingConfiguration()
    }
    
    public func detectCapabilities() async -> DeviceCapabilities {
        // Check LiDAR availability
        let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        
        // Check AR features support
        let supportsMeshAnchors = ARWorldTrackingConfiguration.supports(.meshAnchors)
        let supportsSceneReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        
        // Get Metal capabilities
        guard let device = metalDevice else {
            fatalError("Metal is not supported on this device")
        }
        
        let maxTextureSize = device.maxTextureSize()
        let supportsMSAA = device.supportsMSAA()
        let supportsRayTracing = device.supportsRayTracing()
        let maxThreadgroupSize = device.maxThreadgroupSize()
        let gpuFamily = device.gpuFamily()
        
        return DeviceCapabilities(
            hasLiDAR: hasLiDAR,
            supportsMeshAnchors: supportsMeshAnchors,
            supportsSceneReconstruction: supportsSceneReconstruction,
            maxTextureSize: maxTextureSize,
            supportsMSAA: supportsMSAA,
            supportsRayTracing: supportsRayTracing,
            maxThreadgroupSize: maxThreadgroupSize,
            thermalThrottlingSupported: true,
            gpuFamily: gpuFamily,
            memoryBudget: device.recommendedMaxWorkingSetSize
        )
    }
    
    public func checkScanningSupport() -> ScanningSupport {
        guard let device = metalDevice else {
            return .unsupported(reason: .noMetalSupport)
        }
        
        // Check minimum requirements
        let minimumRequirements = checkMinimumRequirements(device)
        if !minimumRequirements.supported {
            return .unsupported(reason: minimumRequirements.reason)
        }
        
        // Determine optimal scanning mode
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return .supported(recommendedMode: .lidar)
        } else if device.supportsFeatureSet(.iOS_GPUFamily4_v1) {
            return .supported(recommendedMode: .photogrammetry)
        } else {
            return .supported(recommendedMode: .hybrid)
        }
    }
    
    public func getScanningConfiguration() throws -> ScanningConfiguration {
        let capabilities = await detectCapabilities()
        
        // Determine optimal settings based on device capabilities
        let resolution: AppConfiguration.Quality.Resolution
        let compression: AppConfiguration.Quality.Compression
        let detail: AppConfiguration.Quality.Detail
        
        if capabilities.hasLiDAR {
            resolution = .high()
            compression = .lossless
            detail = .maximum
        } else if capabilities.memoryBudget > 4_000_000_000 { // 4GB
            resolution = .medium()
            compression = .high
            detail = .enhanced
        } else {
            resolution = .low()
            compression = .medium
            detail = .standard
        }
        
        return ScanningConfiguration(
            mode: checkScanningSupport().recommendedMode,
            resolution: resolution,
            compression: compression,
            detail: detail
        )
    }
    
    private func checkMinimumRequirements(_ device: MTLDevice) -> (supported: Bool, reason: UnsupportedReason?) {
        // Check iOS version
        if #available(iOS 14.0, *) {
            // Check GPU capability
            if !device.supportsFeatureSet(.iOS_GPUFamily3_v1) {
                return (false, .insufficientGPU)
            }
            
            // Check memory
            if device.recommendedMaxWorkingSetSize < 2_000_000_000 { // 2GB
                return (false, .insufficientMemory)
            }
            
            return (true, nil)
        } else {
            return (false, .unsupportedOS)
        }
    }
}

// MARK: - Supporting Types

public enum ScanningSupport {
    case supported(recommendedMode: ScanningMode)
    case unsupported(reason: UnsupportedReason)
    
    var recommendedMode: ScanningMode {
        switch self {
        case .supported(let mode):
            return mode
        case .unsupported:
            return .photogrammetry // Fallback mode
        }
    }
}

public enum UnsupportedReason: String {
    case unsupportedOS = "iOS 14.0 or later is required"
    case insufficientGPU = "Device GPU is not powerful enough"
    case insufficientMemory = "Insufficient device memory"
    case noMetalSupport = "Metal graphics is not supported"
}

// MARK: - Metal Extensions

private extension MTLDevice {
    func maxTextureSize() -> Int {
        if supportsFeatureSet(.iOS_GPUFamily5_v1) {
            return 16384
        } else if supportsFeatureSet(.iOS_GPUFamily4_v1) {
            return 8192
        } else {
            return 4096
        }
    }
    
    func supportsMSAA() -> Bool {
        return supportsFeatureSet(.iOS_GPUFamily3_v1)
    }
    
    func supportsRayTracing() -> Bool {
        if #available(iOS 14.0, *) {
            return supportsFamily(.apple7)
        }
        return false
    }
    
    func maxThreadgroupSize() -> Int {
        return maximumThreadgroupMemoryLength
    }
    
    func gpuFamily() -> String {
        if #available(iOS 14.0, *) {
            if supportsFamily(.apple7) {
                return "Apple 7"
            } else if supportsFamily(.apple6) {
                return "Apple 6"
            } else if supportsFamily(.apple5) {
                return "Apple 5"
            } else if supportsFamily(.apple4) {
                return "Apple 4"
            } else if supportsFamily(.apple3) {
                return "Apple 3"
            } else {
                return "Apple 2 or lower"
            }
        } else {
            return "Unknown"
        }
    }
}