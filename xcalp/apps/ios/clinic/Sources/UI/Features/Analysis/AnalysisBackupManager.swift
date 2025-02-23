import Foundation

public struct AnalysisBackupManager {
    private let dataManager: AnalysisDataManager
    private let encryptionKey: SymmetricKey
    
    public init() throws {
        self.dataManager = AnalysisDataManager()
        self.encryptionKey = try KeychainManager.shared.getOrCreateBackupKey()
    }
    
    public func createBackup() async throws -> AnalysisBackup {
        // Gather all analysis types
        let types = AnalysisFeature.AnalysisType.allCases
        var backupData: [String: [AnalysisFeature.AnalysisResult]] = [:]
        
        // Collect data for each type
        for type in types {
            let results = try await dataManager.loadAnalysisResults(type: type)
            backupData[type.rawValue] = results
        }
        
        // Create backup metadata
        let metadata = BackupMetadata(
            version: AnalysisFeature.currentVersion,
            timestamp: Date(),
            platform: "iOS",
            analysisCount: backupData.values.map(\.count).reduce(0, +)
        )
        
        // Create and encrypt backup
        let backup = AnalysisBackup(metadata: metadata, data: backupData)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let backupJson = try encoder.encode(backup)
        
        let encryptedData = try CryptoManager.encrypt(
            backupJson,
            using: encryptionKey,
            authenticating: metadata.id.uuidString.data(using: .utf8)!
        )
        
        // Store backup
        try await CloudStorageManager.shared.store(
            encryptedData,
            at: "analysis/backups/\(metadata.id.uuidString)",
            metadata: [
                "version": metadata.version,
                "platform": metadata.platform,
                "timestamp": metadata.timestamp.timeIntervalSince1970
            ]
        )
        
        return backup
    }
    
    public func restoreFromBackup(_ backupId: UUID) async throws {
        // Load encrypted backup
        let encryptedData = try await CloudStorageManager.shared.load(
            from: "analysis/backups/\(backupId.uuidString)"
        )
        
        // Decrypt and verify
        let decryptedData = try CryptoManager.decrypt(
            encryptedData,
            using: encryptionKey,
            authenticating: backupId.uuidString.data(using: .utf8)!
        )
        
        // Parse backup
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AnalysisBackup.self, from: decryptedData)
        
        // Verify version compatibility
        guard backup.metadata.version.isCompatible(with: AnalysisFeature.currentVersion) else {
            throw BackupError.incompatibleVersion
        }
        
        // Restore data
        for (typeString, results) in backup.data {
            guard let type = AnalysisFeature.AnalysisType(rawValue: typeString) else { continue }
            try await dataManager.saveAnalysisResults(results, type: type)
        }
    }
    
    public func listBackups() async throws -> [BackupMetadata] {
        let backups = try await CloudStorageManager.shared.list(prefix: "analysis/backups/")
        return try await withThrowingTaskGroup(of: BackupMetadata?.self) { group in
            for backup in backups {
                group.addTask {
                    guard let metadata = try? await CloudStorageManager.shared.getMetadata(for: backup) else {
                        return nil
                    }
                    return BackupMetadata(
                        id: UUID(uuidString: backup.components(separatedBy: "/").last ?? "") ?? UUID(),
                        version: metadata["version"] as? String ?? "",
                        timestamp: Date(timeIntervalSince1970: metadata["timestamp"] as? Double ?? 0),
                        platform: metadata["platform"] as? String ?? "",
                        analysisCount: metadata["analysisCount"] as? Int ?? 0
                    )
                }
            }
            
            return try await group.compactMap { $0 }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }
}

// MARK: - Supporting Types
public struct AnalysisBackup: Codable {
    let metadata: BackupMetadata
    let data: [String: [AnalysisFeature.AnalysisResult]]
}

public struct BackupMetadata: Codable {
    let id: UUID
    let version: String
    let timestamp: Date
    let platform: String
    let analysisCount: Int
    
    init(
        id: UUID = UUID(),
        version: String,
        timestamp: Date,
        platform: String,
        analysisCount: Int
    ) {
        self.id = id
        self.version = version
        self.timestamp = timestamp
        self.platform = platform
        self.analysisCount = analysisCount
    }
}

enum BackupError: LocalizedError {
    case incompatibleVersion
    case invalidData
    case storageError(Error)
    
    var errorDescription: String? {
        switch self {
        case .incompatibleVersion:
            return NSLocalizedString(
                "backup.error.incompatible_version",
                comment: "Backup version is not compatible with current app version"
            )
        case .invalidData:
            return NSLocalizedString(
                "backup.error.invalid_data",
                comment: "Backup data is invalid or corrupted"
            )
        case .storageError(let error):
            return String(
                format: NSLocalizedString(
                    "backup.error.storage",
                    comment: "Error accessing backup storage: %@"
                ),
                error.localizedDescription
            )
        }
    }
}

private extension String {
    func isCompatible(with other: String) -> Bool {
        let components = self.split(separator: ".")
        let otherComponents = other.split(separator: ".")
        
        // Compare major and minor versions
        guard components.count >= 2, otherComponents.count >= 2,
              components[0] == otherComponents[0],  // Major version must match
              let minor = Int(components[1]),
              let otherMinor = Int(otherComponents[1]) else {
            return false
        }
        
        // Minor version must be less than or equal
        return minor <= otherMinor
    }
}