import CoreData
import Foundation

public struct ScanData: Identifiable, Equatable, Codable {
    public let id: UUID
    public let patientId: UUID
    public let timestamp: Date
    public let quality: Float
    public let meshData: Data
    public let notes: String?
    public let metadata: ScanMetadata
    
    public init(
        id: UUID = UUID(),
        patientId: UUID,
        timestamp: Date = Date(),
        quality: Float,
        meshData: Data,
        notes: String? = nil,
        metadata: ScanMetadata
    ) {
        self.id = id
        self.patientId = patientId
        self.timestamp = timestamp
        self.quality = quality
        self.meshData = meshData
        self.notes = notes
        self.metadata = metadata
    }
}

public struct ScanMetadata: Equatable, Codable {
    public let deviceInfo: DeviceInfo
    public let scanSettings: ScanSettings
    public let environmentInfo: EnvironmentInfo
    
    public init(
        deviceInfo: DeviceInfo,
        scanSettings: ScanSettings,
        environmentInfo: EnvironmentInfo
    ) {
        self.deviceInfo = deviceInfo
        self.scanSettings = scanSettings
        self.environmentInfo = environmentInfo
    }
}

public struct DeviceInfo: Equatable, Codable {
    public let model: String
    public let systemVersion: String
    public let lidarCapabilities: LidarCapabilities
    
    public init(
        model: String,
        systemVersion: String,
        lidarCapabilities: LidarCapabilities
    ) {
        self.model = model
        self.systemVersion = systemVersion
        self.lidarCapabilities = lidarCapabilities
    }
}

public struct LidarCapabilities: Equatable, Codable {
    public let hasSceneReconstruction: Bool
    public let hasPersonSegmentation: Bool
    public let maxMeshResolution: Int
    
    public init(
        hasSceneReconstruction: Bool,
        hasPersonSegmentation: Bool,
        maxMeshResolution: Int
    ) {
        self.hasSceneReconstruction = hasSceneReconstruction
        self.hasPersonSegmentation = hasPersonSegmentation
        self.maxMeshResolution = maxMeshResolution
    }
}

public struct ScanSettings: Equatable, Codable {
    public let resolution: Resolution
    public let accuracy: Accuracy
    public let filteringOptions: FilteringOptions
    
    public init(
        resolution: Resolution,
        accuracy: Accuracy,
        filteringOptions: FilteringOptions
    ) {
        self.resolution = resolution
        self.accuracy = accuracy
        self.filteringOptions = filteringOptions
    }
    
    public enum Resolution: String, Codable {
        case low
        case medium
        case high
    }
    
    public enum Accuracy: String, Codable {
        case fast
        case balanced
        case accurate
    }
    
    public struct FilteringOptions: Equatable, Codable {
        public let smoothing: Bool
        public let removeOutliers: Bool
        public let fillHoles: Bool
        
        public init(
            smoothing: Bool,
            removeOutliers: Bool,
            fillHoles: Bool
        ) {
            self.smoothing = smoothing
            self.removeOutliers = removeOutliers
            self.fillHoles = fillHoles
        }
    }
}

public struct EnvironmentInfo: Equatable, Codable {
    public let lightingCondition: LightingCondition
    public let scanningDistance: Distance
    public let movementQuality: MovementQuality
    
    public init(
        lightingCondition: LightingCondition,
        scanningDistance: Distance,
        movementQuality: MovementQuality
    ) {
        self.lightingCondition = lightingCondition
        self.scanningDistance = scanningDistance
        self.movementQuality = movementQuality
    }
    
    public enum LightingCondition: String, Codable {
        case tooLight
        case tooDark
        case optimal
    }
    
    public enum Distance: String, Codable {
        case tooClose
        case tooFar
        case optimal
    }
    
    public enum MovementQuality: String, Codable {
        case tooFast
        case tooSlow
        case optimal
    }
}

// MARK: - CoreData Support
extension ScanData {
    public init(from entity: ScanEntity) {
        self.id = entity.id ?? UUID()
        self.patientId = entity.patientId ?? UUID()
        self.timestamp = entity.timestamp ?? Date()
        self.quality = entity.quality
        self.meshData = entity.meshData ?? Data()
        self.notes = entity.notes
        
        // Decode metadata
        if let metadataData = entity.metadata,
           let metadata = try? JSONDecoder().decode(ScanMetadata.self, from: metadataData) {
            self.metadata = metadata
        } else {
            // Provide default metadata if decoding fails
            self.metadata = ScanMetadata(
                deviceInfo: DeviceInfo(
                    model: "Unknown",
                    systemVersion: "Unknown",
                    lidarCapabilities: LidarCapabilities(
                        hasSceneReconstruction: false,
                        hasPersonSegmentation: false,
                        maxMeshResolution: 0
                    )
                ),
                scanSettings: ScanSettings(
                    resolution: .medium,
                    accuracy: .balanced,
                    filteringOptions: ScanSettings.FilteringOptions(
                        smoothing: true,
                        removeOutliers: true,
                        fillHoles: true
                    )
                ),
                environmentInfo: EnvironmentInfo(
                    lightingCondition: .optimal,
                    scanningDistance: .optimal,
                    movementQuality: .optimal
                )
            )
        }
    }
    
    public func toEntity(context: NSManagedObjectContext) -> ScanEntity {
        let entity = ScanEntity(context: context)
        entity.id = id
        entity.patientId = patientId
        entity.timestamp = timestamp
        entity.quality = quality
        entity.meshData = meshData
        entity.notes = notes
        
        // Encode metadata
        if let metadataData = try? JSONEncoder().encode(metadata) {
            entity.metadata = metadataData
        }
        
        return entity
    }
}
