import Foundation
import CryptoKit

class BackupManager {
    private let storageManager: StorageManager
    private let encryptionKey: SymmetricKey
    private let compression = CompressionManager()
    
    init(storageManager: StorageManager) throws {
        self.storageManager = storageManager
        self.encryptionKey = try KeychainManager.shared.getOrCreateBackupKey()
    }
    
    func createBackup() async throws -> BackupMetadata {
        let backupId = UUID()
        
        // Collect all scan data
        let scans = try await storageManager.getAllScans()
        
        // Create backup package
        let package = try BackupPackage(
            id: backupId,
            timestamp: Date(),
            scans: scans,
            metadata: getSystemMetadata()
        )
        
        // Compress and encrypt
        let compressedData = try compression.compress(package)
        let encryptedData = try encryptData(compressedData)
        
        // Store backup
        try await storageManager.storeBackup(
            id: backupId,
            data: encryptedData,
            metadata: package.metadata
        )
        
        // Upload to cloud if available
        try await uploadToCloud(backupId: backupId, data: encryptedData)
        
        return package.metadata
    }
    
    func restore(from backupId: UUID) async throws {
        // Fetch backup data
        let (encryptedData, metadata) = try await storageManager.retrieveBackup(id: backupId)
        
        // Decrypt and decompress
        let decryptedData = try decryptData(encryptedData)
        let package = try compression.decompress(decryptedData)
        
        // Verify integrity
        try verifyBackupIntegrity(package)
        
        // Restore data
        try await restoreFromPackage(package)
    }
    
    func listBackups() async throws -> [BackupMetadata] {
        return try await storageManager.listBackups()
    }
    
    // Auto-backup configuration
    func configureAutoBackup(schedule: BackupSchedule) throws {
        let config = BackupConfiguration(
            schedule: schedule,
            retentionPolicy: RetentionPolicy(
                maxBackups: 10,
                maxAge: 30 // days
            )
        )
        
        try storageManager.saveBackupConfig(config)
        scheduleNextBackup(config)
    }
}

private extension BackupManager {
    func encryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined ?? Data()
    }
    
    func decryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
    
    func verifyBackupIntegrity(_ package: BackupPackage) throws {
        // Verify checksums
        let calculatedHash = SHA256.hash(data: package.serializedData)
        guard calculatedHash == package.metadata.checksum else {
            throw BackupError.integrityCheckFailed
        }
        
        // Verify version compatibility
        let versionControl = VersionControlManager()
        let compatibility = versionControl.checkCompatibility(data: package.metadata.version)
        guard case .compatible = compatibility else {
            throw BackupError.incompatibleVersion
        }
    }
    
    func restoreFromPackage(_ package: BackupPackage) async throws {
        // Begin transaction
        try await storageManager.beginTransaction()
        
        do {
            // Clear existing data
            try await storageManager.clearAllData()
            
            // Restore scans
            for scan in package.scans {
                try await storageManager.storeScan(scan)
            }
            
            // Commit transaction
            try await storageManager.commitTransaction()
            
        } catch {
            // Rollback on failure
            try await storageManager.rollbackTransaction()
            throw error
        }
    }
    
    func getSystemMetadata() -> SystemMetadata {
        return SystemMetadata(
            appVersion: AppVersion.current,
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            timestamp: Date()
        )
    }
}

enum BackupError: Error {
    case encryptionFailed
    case decryptionFailed
    case compressionFailed
    case decompressionFailed
    case integrityCheckFailed
    case incompatibleVersion
    case storageFailed
    case restoreFailed
    case invalidBackup
}