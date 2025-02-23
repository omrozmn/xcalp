import ARKit

class SensorCapabilityManager {
    enum ScannerType {
        case lidar
        case trueDepth
        case none
    }
    
    static func getScannerType() -> ScannerType {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            return .lidar
        } else if ARFaceTrackingConfiguration.isSupported {
            return .trueDepth
        }
        return .none
    }
    
    static func isScanningSupported() -> Bool {
        return getScannerType() != .none
    }
    
    static func getMinimumQualityThreshold(for scannerType: ScannerType) -> Float {
        switch scannerType {
        case .lidar:
            return 0.8 // Higher threshold for LiDAR
        case .trueDepth:
            return 0.6 // Lower threshold for TrueDepth
        case .none:
            return 0.0 // No scanning supported
        }
    }
    
    static func getFeatureAvailability(for scannerType: ScannerType) -> [String: Bool] {
        switch scannerType {
        case .lidar:
            return [
                "highPrecisionMapping": true,
                "detailedMeshGeneration": true,
                "realTimeDepthAnalysis": true
            ]
        case .trueDepth:
            return [
                "highPrecisionMapping": false,
                "detailedMeshGeneration": true,
                "realTimeDepthAnalysis": true
            ]
        case .none:
            return [
                "highPrecisionMapping": false,
                "detailedMeshGeneration": false,
                "realTimeDepthAnalysis": false
            ]
        }
    }
}
