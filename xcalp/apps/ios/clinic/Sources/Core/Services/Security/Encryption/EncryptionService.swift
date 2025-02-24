import CryptoKit
import Foundation
import Security

public final class EncryptionService {
    public static let shared = EncryptionService()
    
    private let keychain = KeychainManager()
    private let keyPrefix = "com.xcalp.clinic.encryption."
    private let queue = DispatchQueue(label: "com.xcalp.clinic.encryption", qos: .userInitiated)
    
    private init() {}
    
    /// Generate a new encryption key
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: Generated SymmetricKey
    public func generateKey(identifier: String) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try storeKey(key, identifier: identifier)
        return key
    }
    
    /// Store an encryption key securely
    /// - Parameters:
    ///   - key: Key to store
    ///   - identifier: Unique identifier for the key
    public func storeKey(_ key: SymmetricKey, identifier: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychain.store(keyData, forKey: keyPrefix + identifier)
        
        // Log HIPAA event
        HIPAALogger.shared.log(
            type: .security,
            action: "key_stored",
            userID: AuthenticationService.shared.currentSession?.userID ?? "system",
            details: "Key ID: \(identifier)"
        )
    }
    
    /// Retrieve a stored encryption key
    /// - Parameter identifier: Identifier of key to retrieve
    /// - Returns: Retrieved SymmetricKey
    public func retrieveKey(identifier: String) throws -> SymmetricKey {
        guard let keyData = try keychain.retrieve(forKey: keyPrefix + identifier) else {
            throw EncryptionError.keyNotFound
        }
        return SymmetricKey(data: keyData)
    }
    
    /// Encrypt data using AES-GCM
    /// - Parameters:
    ///   - data: Data to encrypt
    ///   - key: Key to use for encryption
    /// - Returns: Encrypted data
    public func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined ?? Data()
    }
    
    /// Decrypt data using AES-GCM
    /// - Parameters:
    ///   - data: Data to decrypt
    ///   - key: Key to use for decryption
    /// - Returns: Decrypted data
    public func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Rotate encryption keys periodically
    /// - Parameter interval: Time interval for key rotation (default: 90 days)
    public func setupKeyRotation(interval: TimeInterval = 90 * 24 * 60 * 60) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.rotateKeys()
        }
    }
    
    private func rotateKeys() {
        queue.async {
            do {
                // Get all encryption keys
                let keys = try self.keychain.retrieveAll()
                    .filter { $0.key.hasPrefix(self.keyPrefix) }
                
                // Generate new keys and re-encrypt data
                for (identifier, oldKeyData) in keys {
                    let oldKey = SymmetricKey(data: oldKeyData)
                    let newKey = try self.generateKey(identifier: identifier)
                    
                    // TODO: Re-encrypt data using new key
                    // This would involve:
                    // 1. Retrieving all data encrypted with old key
                    // 2. Decrypting with old key
                    // 3. Encrypting with new key
                    // 4. Storing updated data
                    
                    // Log key rotation
                    HIPAALogger.shared.log(
                        type: .security,
                        action: "key_rotated",
                        userID: AuthenticationService.shared.currentSession?.userID ?? "system",
                        details: "Key ID: \(identifier)"
                    )
                }
            } catch {
                // Log key rotation failure
                HIPAALogger.shared.log(
                    type: .security,
                    action: "key_rotation_failed",
                    userID: AuthenticationService.shared.currentSession?.userID ?? "system",
                    details: error.localizedDescription
                )
            }
        }
    }
}

private final class KeychainManager {
    func store(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try update(data, forKey: key)
        } else if status != errSecSuccess {
            throw EncryptionError.keychainError(status)
        }
    }
    
    func update(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }
    
    func retrieve(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        } else if status != errSecSuccess {
            throw EncryptionError.keychainError(status)
        }
        
        return result as? Data
    }
    
    func retrieveAll() throws -> [String: Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return [:]
        } else if status != errSecSuccess {
            throw EncryptionError.keychainError(status)
        }
        
        guard let items = result as? [[String: Any]] else {
            return [:]
        }
        
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let key = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else {
                return nil
            }
            return (key, data)
        })
    }
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }
}

public enum EncryptionError: LocalizedError {
    case keyNotFound
    case encryptionFailed
    case decryptionFailed
    case keychainError(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .keyNotFound:
            return "Encryption key not found"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
