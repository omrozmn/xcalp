import CryptoKit
import Dependencies
import Foundation
import KeychainAccess

/// Service for securely storing sensitive data following HIPAA requirements
public final class SecureStorageService {
    public static let shared = SecureStorageService()
    
    private let keychain = Keychain(service: "com.xcalp.clinic")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let encryption = HIPAAEncryptionService.shared
    private let logger = LoggingService.shared
    
    private lazy var secureStorageURL: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SecureStorage", isDirectory: true)
    }()
    
    private init() {
        setupEncryption()
        setupSecureStorage()
    }
    
    /// Store data securely with encryption
    /// - Parameters:
    ///   - data: Data to store
    ///   - key: Key to store data under
    ///   - accessLevel: Required access level
    public func store<T: Codable>(_ data: T, forKey key: String, accessLevel: HIPAACompliance.AccessLevel) async throws {
        // Check access permissions
        guard try await HIPAACompliance.shared.validateAccess(accessLevel) else {
            throw StorageError.accessDenied
        }
        
        let jsonData = try encoder.encode(data)
        let encryptedData = try HIPAACompliance.shared.encryptData(jsonData)
        
        try keychain
            .accessibility(.whenUnlocked)
            .set(encryptedData, key: key)
        
        // Log HIPAA event
        AnalyticsService.shared.logHIPAAEvent(
            action: .modify,
            resourceType: String(describing: T.self),
            resourceId: key,
            userId: UserSession.shared.currentUserId
        )
    }
    
    /// Retrieve securely stored data
    /// - Parameters:
    ///   - key: Key to retrieve data for
    ///   - accessLevel: Required access level
    /// - Returns: Decrypted data of specified type
    public func retrieve<T: Codable>(forKey key: String, accessLevel: HIPAACompliance.AccessLevel) async throws -> T {
        // Check access permissions
        guard try await HIPAACompliance.shared.validateAccess(accessLevel) else {
            throw StorageError.accessDenied
        }
        
        guard let encryptedData = try keychain.getData(key) else {
            throw StorageError.dataNotFound
        }
        
        let decryptedData = try HIPAACompliance.shared.decryptData(encryptedData)
        let result = try decoder.decode(T.self, from: decryptedData)
        
        // Log HIPAA event
        AnalyticsService.shared.logHIPAAEvent(
            action: .view,
            resourceType: String(describing: T.self),
            resourceId: key,
            userId: UserSession.shared.currentUserId
        )
        
        return result
    }
    
    /// Delete securely stored data
    /// - Parameters:
    ///   - key: Key to delete data for
    ///   - accessLevel: Required access level
    public func delete(forKey key: String, accessLevel: HIPAACompliance.AccessLevel) async throws {
        // Check access permissions
        guard try await HIPAACompliance.shared.validateAccess(accessLevel) else {
            throw StorageError.accessDenied
        }
        
        try keychain.remove(key)
        
        // Log HIPAA event
        AnalyticsService.shared.logHIPAAEvent(
            action: .delete,
            resourceType: "StoredData",
            resourceId: key,
            userId: UserSession.shared.currentUserId
        )
    }
    
    // MARK: - Private Methods
    
    private func setupEncryption() {
        // Generate encryption key if needed
        if try? keychain.getData("masterKey") == nil {
            let key = SymmetricKey(size: .bits256)
            try? keychain
                .accessibility(.whenUnlocked)
                .set(key.withUnsafeBytes { Data($0) }, key: "masterKey")
        }
    }
    
    private func setupSecureStorage() {
        do {
            try fileManager.createDirectory(
                at: secureStorageURL,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.complete
                ]
            )
            
            logger.logSecurityEvent(
                "Secure storage directory created",
                level: .info,
                metadata: ["path": secureStorageURL.path]
            )
        } catch {
            logger.logSecurityEvent(
                "Failed to create secure storage directory",
                level: .critical,
                metadata: ["error": error.localizedDescription]
            )
        }
    }
    
    public func store<T: Codable>(_ data: T, type: DataType, identifier: String) throws {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        
        let encrypted = try encryption.encrypt(jsonData, type: type)
        let fileURL = storageURL(for: identifier, type: type)
        
        try encrypted.data.write(to: fileURL, options: .completeFileProtection)
        
        logger.logHIPAAEvent(
            "Data stored securely",
            type: .modification,
            metadata: [
                "type": type.rawValue,
                "identifier": identifier,
                "size": encrypted.data.count
            ]
        )
    }
    
    public func retrieve<T: Codable>(_ type: DataType, identifier: String) throws -> T {
        let fileURL = storageURL(for: identifier, type: type)
        let encryptedData = try Data(contentsOf: fileURL)
        
        let encrypted = EncryptedData(
            data: encryptedData,
            dataKey: try retrieveDataKey(for: identifier, type: type),
            type: type,
            timestamp: try fileModificationDate(for: fileURL)
        )
        
        let decrypted = try encryption.decrypt(encrypted)
        let decoder = JSONDecoder()
        let result = try decoder.decode(T.self, from: decrypted)
        
        logger.logHIPAAEvent(
            "Data retrieved",
            type: .access,
            metadata: [
                "type": type.rawValue,
                "identifier": identifier,
                "size": decrypted.count
            ]
        )
        
        return result
    }
    
    public func delete(_ type: DataType, identifier: String) throws {
        let fileURL = storageURL(for: identifier, type: type)
        try fileManager.removeItem(at: fileURL)
        
        logger.logHIPAAEvent(
            "Data deleted",
            type: .deletion,
            metadata: [
                "type": type.rawValue,
                "identifier": identifier
            ]
        )
    }
    
    private func storageURL(for identifier: String, type: DataType) -> URL {
        secureStorageURL
            .appendingPathComponent(type.rawValue)
            .appendingPathComponent(identifier)
    }
    
    private func retrieveDataKey(for identifier: String, type: DataType) throws -> Data {
        let keyURL = secureStorageURL
            .appendingPathComponent("keys")
            .appendingPathComponent("\(type.rawValue)_\(identifier).key")
        
        return try Data(contentsOf: keyURL)
    }
    
    private func fileModificationDate(for url: URL) throws -> Date {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? Date()
    }
}

// MARK: - Supporting Types
extension SecureStorageService {
    public enum StorageError: LocalizedError {
        case accessDenied
        case dataNotFound
        case encryptionFailed
        case decryptionFailed
        
        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Access denied to secure storage"
            case .dataNotFound:
                return "Requested data not found in secure storage"
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            }
        }
    }
}

// MARK: - UserSession (Temporary Mock)
private enum UserSession {
    static var shared = UserSession()
    var currentUserId: String = "temp-user-id"
    private init() {}
}

// MARK: - Dependency Interface

private enum SecureStorageKey: DependencyKey {
    static let liveValue = SecureStorageService.shared
}

extension DependencyValues {
    var secureStorage: SecureStorageService {
        get { self[SecureStorageKey.self] }
        set { self[SecureStorageKey.self] = newValue }
    }
}
