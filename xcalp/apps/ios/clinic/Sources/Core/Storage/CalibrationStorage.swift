import Foundation
import CoreData
import CryptoKit

public actor CalibrationStorage {
    public static let shared = CalibrationStorage()
    
    private let secureStorage: SecureStorageService
    private let analytics: AnalyticsService
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "CalibrationStorage")
    
    private let storageDirectory: URL
    private let schemaVersion: Int = 1
    
    private init(
        secureStorage: SecureStorageService = .shared,
        analytics: AnalyticsService = .shared
    ) {
        self.secureStorage = secureStorage
        self.analytics = analytics
        
        // Setup storage directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageDirectory = appSupport.appendingPathComponent("CalibrationData", isDirectory: true)
        
        setupStorage()
    }
    
    public func saveCalibrationProfile(
        _ profile: CalibrationProfile
    ) async throws {
        let startTime = Date()
        
        // Encrypt profile data
        let encryptedData = try await secureStorage.performSecureOperation {
            try encryptProfileData(profile)
        }
        
        // Generate integrity hash
        let integrityHash = generateIntegrityHash(for: profile)
        
        // Create metadata
        let metadata = ProfileMetadata(
            id: profile.id,
            version: schemaVersion,
            createdAt: profile.createdAt,
            updatedAt: Date(),
            hash: integrityHash
        )
        
        // Save to storage
        try await saveProfile(
            data: encryptedData,
            metadata: metadata,
            profile: profile
        )
        
        let saveTime = Date().timeIntervalSince(startTime)
        
        analytics.track(
            event: .calibrationProfileSaved,
            properties: [
                "profileId": profile.id.uuidString,
                "environment": profile.environment.rawValue,
                "saveTime": saveTime
            ]
        )
    }
    
    public func loadCalibrationProfile(
        id: UUID
    ) async throws -> CalibrationProfile {
        // Load encrypted data
        let (encryptedData, metadata) = try await loadProfileData(id)
        
        // Decrypt profile
        let profile = try await secureStorage.performSecureOperation {
            try decryptProfileData(encryptedData, metadata: metadata)
        }
        
        // Verify integrity
        try verifyProfileIntegrity(profile, hash: metadata.hash)
        
        analytics.track(
            event: .calibrationProfileLoaded,
            properties: [
                "profileId": id.uuidString,
                "environment": profile.environment.rawValue
            ]
        )
        
        return profile
    }
    
    public func listCalibrationProfiles(
        for environment: ScanCalibrationManager.EnvironmentType? = nil
    ) async throws -> [ProfileSummary] {
        let profiles = try await loadProfileSummaries()
        
        if let environment = environment {
            return profiles.filter { $0.environment == environment }
        }
        
        return profiles
    }
    
    public func deleteCalibrationProfile(_ id: UUID) async throws {
        // Delete profile data
        try await deleteProfileData(id)
        
        analytics.track(
            event: .calibrationProfileDeleted,
            properties: ["profileId": id.uuidString]
        )
    }
    
    public func pruneOldProfiles(olderThan age: TimeInterval) async throws {
        let cutoffDate = Date().addingTimeInterval(-age)
        let deletedCount = try await deleteOldProfiles(before: cutoffDate)
        
        analytics.track(
            event: .oldProfilesPruned,
            properties: [
                "cutoffDate": cutoffDate,
                "deletedCount": deletedCount
            ]
        )
    }
    
    private func encryptProfileData(_ profile: CalibrationProfile) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        
        // Additional encryption logic here
        return data
    }
    
    private func decryptProfileData(
        _ data: Data,
        metadata: ProfileMetadata
    ) throws -> CalibrationProfile {
        // Decrypt data
        let decrypted = data // Add decryption logic
        
        let decoder = JSONDecoder()
        return try decoder.decode(CalibrationProfile.self, from: decrypted)
    }
    
    private func generateIntegrityHash(for profile: CalibrationProfile) -> Data {
        var hashData = Data()
        
        // Combine profile data for hashing
        hashData.append(profile.id.uuidString.data(using: .utf8)!)
        hashData.append(profile.environment.rawValue.data(using: .utf8)!)
        hashData.append(withUnsafeBytes(of: profile.createdAt.timeIntervalSince1970) { Data($0) })
        
        let hash = SHA256.hash(data: hashData)
        return Data(hash)
    }
    
    private func verifyProfileIntegrity(
        _ profile: CalibrationProfile,
        hash: Data
    ) throws {
        let computedHash = generateIntegrityHash(for: profile)
        
        guard computedHash == hash else {
            throw StorageError.integrityCheckFailed
        }
    }
    
    private func saveProfile(
        data: Data,
        metadata: ProfileMetadata,
        profile: CalibrationProfile
    ) async throws {
        let profileURL = storageDirectory.appendingPathComponent(
            "\(profile.id.uuidString).calibration"
        )
        
        let metadataURL = storageDirectory.appendingPathComponent(
            "\(profile.id.uuidString).metadata"
        )
        
        // Save profile data
        try data.write(to: profileURL)
        
        // Save metadata
        let encoder = JSONEncoder()
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL)
    }
    
    private func loadProfileData(
        _ id: UUID
    ) async throws -> (Data, ProfileMetadata) {
        let profileURL = storageDirectory.appendingPathComponent(
            "\(id.uuidString).calibration"
        )
        
        let metadataURL = storageDirectory.appendingPathComponent(
            "\(id.uuidString).metadata"
        )
        
        // Load profile data
        let profileData = try Data(contentsOf: profileURL)
        
        // Load and decode metadata
        let metadataData = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(ProfileMetadata.self, from: metadataData)
        
        return (profileData, metadata)
    }
    
    private func loadProfileSummaries() async throws -> [ProfileSummary] {
        let fileManager = FileManager.default
        let metadataFiles = try fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "metadata" }
        
        return try await withThrowingTaskGroup(of: ProfileSummary?.self) { group in
            for url in metadataFiles {
                group.addTask {
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        let metadata = try decoder.decode(ProfileMetadata.self, from: data)
                        
                        // Load minimal profile info
                        let profile = try await self.loadCalibrationProfile(id: metadata.id)
                        
                        return ProfileSummary(
                            id: profile.id,
                            environment: profile.environment,
                            createdAt: profile.createdAt,
                            updatedAt: metadata.updatedAt
                        )
                    } catch {
                        self.logger.error("Failed to load profile summary: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            var summaries: [ProfileSummary] = []
            for try await summary in group {
                if let summary = summary {
                    summaries.append(summary)
                }
            }
            return summaries
        }
    }
    
    private func deleteProfileData(_ id: UUID) async throws {
        let profileURL = storageDirectory.appendingPathComponent(
            "\(id.uuidString).calibration"
        )
        
        let metadataURL = storageDirectory.appendingPathComponent(
            "\(id.uuidString).metadata"
        )
        
        try FileManager.default.removeItem(at: profileURL)
        try FileManager.default.removeItem(at: metadataURL)
    }
    
    private func deleteOldProfiles(before date: Date) async throws -> Int {
        var deletedCount = 0
        let summaries = try await loadProfileSummaries()
        
        for summary in summaries where summary.createdAt < date {
            try await deleteCalibrationProfile(summary.id)
            deletedCount += 1
        }
        
        return deletedCount
    }
    
    private func setupStorage() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try? fileManager.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )
        }
        
        // Set file protection
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? storageDirectory.setResourceValues(resourceValues)
    }
}

// MARK: - Types

extension CalibrationStorage {
    public struct CalibrationProfile: Codable {
        let id: UUID
        let environment: ScanCalibrationManager.EnvironmentType
        let parameters: ScanCalibrationManager.CalibrationParameters
        let createdAt: Date
        var statistics: CalibrationStatistics
        var optimizationHistory: [OptimizationRecord]
        
        struct CalibrationStatistics: Codable {
            var successfulScans: Int
            var averageAccuracy: Float
            var lastUsed: Date
        }
        
        struct OptimizationRecord: Codable {
            let timestamp: Date
            let adjustments: [String: Float]
            let accuracy: Float
        }
    }
    
    struct ProfileMetadata: Codable {
        let id: UUID
        let version: Int
        let createdAt: Date
        let updatedAt: Date
        let hash: Data
    }
    
    public struct ProfileSummary {
        let id: UUID
        let environment: ScanCalibrationManager.EnvironmentType
        let createdAt: Date
        let updatedAt: Date
    }
    
    enum StorageError: LocalizedError {
        case profileNotFound
        case integrityCheckFailed
        case invalidData
        case storageError
        
        var errorDescription: String? {
            switch self {
            case .profileNotFound:
                return "Calibration profile not found"
            case .integrityCheckFailed:
                return "Profile integrity check failed"
            case .invalidData:
                return "Invalid profile data"
            case .storageError:
                return "Storage operation failed"
            }
        }
    }
}

extension AnalyticsService.Event {
    static let calibrationProfileSaved = AnalyticsService.Event(name: "calibration_profile_saved")
    static let calibrationProfileLoaded = AnalyticsService.Event(name: "calibration_profile_loaded")
    static let calibrationProfileDeleted = AnalyticsService.Event(name: "calibration_profile_deleted")
    static let oldProfilesPruned = AnalyticsService.Event(name: "old_profiles_pruned")
}