import CryptoKit
import Dependencies
import Foundation

public final class KeyRotationManager {
    public static let shared = KeyRotationManager()
    
    private let encryptionService: HIPAAEncryptionService
    private let storage: SecureStorageService
    private let logger: LoggingService
    
    private var rotationTimer: Timer?
    private let rotationInterval: TimeInterval = 90 * 24 * 3600 // 90 days
    
    private init() {
        self.encryptionService = HIPAAEncryptionService.shared
        self.storage = SecureStorageService.shared
        self.logger = LoggingService.shared
        setupKeyRotation()
    }
    
    public func rotateKeys() async throws {
        logger.logSecurityEvent(
            "Starting key rotation",
            level: .info
        )
        
        // Generate new master key
        let newMasterKey = SymmetricKey(size: .bits256)
        
        // Get all encrypted data
        let encryptedData = try await getAllEncryptedData()
        
        // Re-encrypt all data with new key
        for var data in encryptedData {
            // Decrypt with old key
            let decrypted = try encryptionService.decrypt(data)
            
            // Re-encrypt with new key
            data = try encryptionService.encrypt(decrypted, type: data.type)
            
            // Store updated data
            try storage.store(data, type: data.type, identifier: data.metadata["identifier"] as! String)
        }
        
        // Store new master key
        try storeNewMasterKey(newMasterKey)
        
        logger.logSecurityEvent(
            "Key rotation completed",
            level: .info,
            metadata: [
                "dataCount": encryptedData.count,
                "timestamp": Date()
            ]
        )
    }
    
    public func forceKeyRotation() async throws {
        try await rotateKeys()
        resetRotationTimer()
    }
    
    // MARK: - Private Methods
    
    private func setupKeyRotation() {
        checkAndScheduleRotation()
        
        // Setup daily check
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.checkAndScheduleRotation()
        }
    }
    
    private func checkAndScheduleRotation() {
        Task {
            do {
                let metadata = try encryptionService.getMasterKeyMetadata()
                if let lastRotation = metadata.lastRotationDate {
                    let age = Date().timeIntervalSince(lastRotation)
                    if age >= rotationInterval {
                        try await rotateKeys()
                    }
                }
            } catch {
                logger.logSecurityEvent(
                    "Failed to check key rotation",
                    level: .error,
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
    }
    
    private func getAllEncryptedData() async throws -> [EncryptedData] {
        // Implementation would fetch all encrypted data from storage
        // This is a placeholder that would need to be implemented based on your storage structure
        []
    }
    
    private func storeNewMasterKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try encryptionService.updateMasterKey(keyData)
    }
    
    private func resetRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        setupKeyRotation()
    }
}

// MARK: - Dependency Interface

private enum KeyRotationManagerKey: DependencyKey {
    static let liveValue = KeyRotationManager.shared
}

extension DependencyValues {
    var keyRotation: KeyRotationManager {
        get { self[KeyRotationManagerKey.self] }
        set { self[KeyRotationManagerKey.self] = newValue }
    }
}

// MARK: - HIPAAEncryptionService Extension

extension HIPAAEncryptionService {
    func updateMasterKey(_ keyData: Data) throws {
        try keychain.set(keyData, key: "master_key")
        
        logger.logSecurityEvent(
            "Master key updated",
            level: .info,
            metadata: ["timestamp": Date()]
        )
    }
}
