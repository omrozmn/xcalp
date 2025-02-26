import Foundation
import Security
import CryptoKit

actor SecureStorage {
    static let shared = SecureStorage()
    private let queue = DispatchQueue(label: "com.xcalp.clinic.storage", qos: .userInitiated)
    private let keychain = KeychainManager.shared
    
    enum ExpiryDuration {
        case hours(_ hours: Int)
        case days(_ days: Int)
        case never
        
        var timeInterval: TimeInterval? {
            switch self {
            case .hours(let hours):
                return TimeInterval(hours * 3600)
            case .days(let days):
                return TimeInterval(days * 24 * 3600)
            case .never:
                return nil
            }
        }
    }
    
    private init() {}
    
    func store<T: Codable>(_ value: T, forKey key: String, expires: ExpiryDuration = .never) async throws {
        let data = try JSONEncoder().encode(StorageEntry(value: value, expires: expires))
        let encrypted = try encrypt(data)
        
        try await queue.enqueue {
            try self.keychain.save(encrypted, forKey: key)
        }
    }
    
    func retrieve<T: Codable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let encrypted = try await queue.enqueue({ try self.keychain.read(forKey: key) }) else {
            return nil
        }
        
        let data = try decrypt(encrypted)
        let entry = try JSONDecoder().decode(StorageEntry<T>.self, from: data)
        
        guard !entry.isExpired else {
            try await remove(forKey: key)
            return nil
        }
        
        return entry.value
    }
    
    func remove(forKey key: String) async throws {
        try await queue.enqueue {
            try self.keychain.delete(forKey: key)
        }
    }
    
    private func encrypt(_ data: Data) throws -> Data {
        guard let key = try keychain.getEncryptionKey() else {
            throw StorageError.encryptionKeyMissing
        }
        
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined ?? Data()
    }
    
    private func decrypt(_ data: Data) throws -> Data {
        guard let key = try keychain.getEncryptionKey() else {
            throw StorageError.encryptionKeyMissing
        }
        
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
}

// MARK: - Supporting Types

private struct StorageEntry<T: Codable>: Codable {
    let value: T
    let expiresAt: Date?
    
    init(value: T, expires: SecureStorage.ExpiryDuration) {
        self.value = value
        if let interval = expires.timeInterval {
            self.expiresAt = Date().addingTimeInterval(interval)
        } else {
            self.expiresAt = nil
        }
    }
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}

enum StorageError: LocalizedError {
    case encryptionKeyMissing
    case encryptionFailed
    case decryptionFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .encryptionKeyMissing:
            return "Encryption key not found in keychain"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .invalidData:
            return "Data is invalid or corrupted"
        }
    }
}