import ARKit
import Foundation

public final class DeviceCapabilityChecker {
    public static let shared = DeviceCapabilityChecker()
    
    private init() {}
    
    public var hasLiDAR: Bool {
        if #available(iOS 13.4, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        return false
    }
    
    public var hasTrueDepth: Bool {
        return ARFaceTrackingConfiguration.isSupported
    }
    
    public var canUseFrontCamera: Bool {
        return hasTrueDepth // Always allow front camera if TrueDepth is available
    }
    
    public var canUseBackCamera: Bool {
        return hasLiDAR // Only allow back camera if LiDAR is available
    }
    
    public func validateScanningCapabilities() -> ScanningCapabilities {
        return ScanningCapabilities(
            hasTrueDepth: hasTrueDepth,
            hasLiDAR: hasLiDAR,
            availableCameras: availableCameras,
            preferredScanningMode: determinePreferredMode()
        )
    }
    
    private var availableCameras: Set<ScanningCamera> {
        var cameras = Set<ScanningCamera>()
        if canUseFrontCamera {
            cameras.insert(.front)
        }
        if canUseBackCamera {
            cameras.insert(.back)
        }
        return cameras
    }
    
    private func determinePreferredMode() -> ScanningMode {
        if hasLiDAR {
            return .lidar
        } else if hasTrueDepth {
            return .trueDepth
        } else {
            return .unsupported
        }
    }
}

public struct ScanningCapabilities {
    public let hasTrueDepth: Bool
    public let hasLiDAR: Bool
    public let availableCameras: Set<ScanningCamera>
    public let preferredScanningMode: ScanningMode
}

public enum ScanningCamera {
    case front
    case back
}

public enum ScanningMode {
    case lidar
    case trueDepth
    case unsupported
}