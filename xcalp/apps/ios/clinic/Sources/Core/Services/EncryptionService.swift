import Foundation
import CryptoKit
import Security

public actor EncryptionService {
    public static let shared = EncryptionService()
    
    private let keychain: KeychainService
    private let errorHandler: ErrorHandler
    private var activeKey: SymmetricKey?
    private let keyRotationInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    private init(
        keychain: KeychainService = .shared,
        errorHandler: ErrorHandler = .shared
    ) {
        self.keychain = keychain
        self.errorHandler = errorHandler
        setupEncryption()
    }
    
    public func encrypt(_ data: Data) throws -> Data {
        guard let key = activeKey else {
            throw EncryptionError.noActiveKey
        }
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed
            }
            return combined
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    public func decrypt(_ data: Data) throws -> Data {
        guard let key = activeKey else {
            throw EncryptionError.noActiveKey
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw errorHandler.handle(error)
        }
    }
    
    public func rotateKey() async throws {
        let newKey = generateKey()
        let oldKey = activeKey
        
        // Store new key
        try await keychain.store(
            key: newKey.withUnsafeBytes { Data($0) },
            service: "com.xcalp.clinic.encryption",
            label: "Active Encryption Key"
        )
        
        // Update active key
        activeKey = newKey
        
        // Log key rotation
        await HIPAALogger.shared.log(
            event: .encryptionKeyRotated,
            details: [
                "action": "Key Rotation",
                "timestamp": Date()
            ]
        )
        
        // Schedule next rotation
        scheduleKeyRotation()
    }
    
    private func setupEncryption() {
        Task {
            do {
                // Try to load existing key
                if let keyData = try await keychain.load(
                    service: "com.xcalp.clinic.encryption"
                ) {
                    activeKey = SymmetricKey(data: keyData)
                } else {
                    // Generate and store new key if none exists
                    try await rotateKey()
                }
                
                // Schedule key rotation
                scheduleKeyRotation()
            } catch {
                await errorHandler.handle(error)
            }
        }
    }
    
    private func generateKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    private func scheduleKeyRotation() {
        Task {
            try await Task.sleep(nanoseconds: UInt64(keyRotationInterval) * 1_000_000_000)
            try await rotateKey()
        }
    }
}

// MARK: - Types

extension EncryptionService {
    public enum EncryptionError: LocalizedError {
        case noActiveKey
        case encryptionFailed
        case decryptionFailed
        case keyRotationFailed
        
        public var errorDescription: String? {
            switch self {
            case .noActiveKey:
                return "No active encryption key available"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .keyRotationFailed:
                return "Failed to rotate encryption key"
            }
        }
    }
}

extension HIPAALogger.Event {
    static let encryptionKeyRotated = HIPAALogger.Event(
        name: "encryption_key_rotated",
        isSecuritySensitive: true
    )
}