import Foundation
import CoreData
import CryptoKit
import Security

public actor SecureStorageService {
    public static let shared = SecureStorageService()
    
    private let container: NSPersistentContainer
    private let encryptionKey: SymmetricKey
    private let errorHandler: ErrorHandler
    
    private init(errorHandler: ErrorHandler = .shared) {
        self.errorHandler = errorHandler
        
        // Initialize CoreData
        container = NSPersistentContainer(name: "XcalpClinic")
        
        // Configure encryption
        if let key = try? loadEncryptionKey() {
            self.encryptionKey = key
        } else {
            self.encryptionKey = generateEncryptionKey()
            try? saveEncryptionKey(self.encryptionKey)
        }
        
        // Setup persistent store with encryption
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreFileProtectionKey)
        container.persistentStoreDescriptions = [storeDescription]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
    }
    
    var mainContext: NSManagedObjectContext {
        container.viewContext
    }
    
    public func performSecureOperation<T>(_ operation: () throws -> T) throws -> T {
        let result = try operation()
        
        if let data = try? JSONSerialization.data(withJSONObject: ["timestamp": Date()]) {
            let signature = try generateSignature(for: data)
            try verifyDataIntegrity(data: data, signature: signature)
        }
        
        return result
    }
    
    public func saveSecurely() async throws {
        try await Task {
            if mainContext.hasChanges {
                // Generate audit trail
                let changes = mainContext.insertedObjects.union(mainContext.updatedObjects)
                let auditTrail = generateAuditTrail(for: Array(changes))
                
                // Save context
                try mainContext.save()
                
                // Store audit trail
                try storeAuditTrail(auditTrail)
            }
        }.value
    }
    
    // MARK: - Encryption
    
    private func encrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        return sealedBox.combined ?? Data()
    }
    
    private func decrypt(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
    
    private func generateSignature(for data: Data) throws -> Data {
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: encryptionKey)
        return Data(signature)
    }
    
    private func verifyDataIntegrity(data: Data, signature: Data) throws {
        let computedSignature = try generateSignature(for: data)
        guard signature == computedSignature else {
            throw StorageError.integrityCheckFailed
        }
    }
    
    // MARK: - Key Management
    
    private func generateEncryptionKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    private func loadEncryptionKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.xcalp.clinic.encryption",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let keyData = result as? Data else {
            return nil
        }
        
        return SymmetricKey(data: keyData)
    }
    
    private func saveEncryptionKey(_ key: SymmetricKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.xcalp.clinic.encryption",
            kSecValueData as String: key.withUnsafeBytes { Data($0) }
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StorageError.keyStorageFailed
        }
    }
    
    // MARK: - Audit Trail
    
    private func generateAuditTrail(for objects: [NSManagedObject]) -> AuditTrail {
        return AuditTrail(
            timestamp: Date(),
            userID: SessionManager.shared.currentUser?.id ?? "unknown",
            changes: objects.map { object in
                AuditTrail.Change(
                    entityName: object.entity.name ?? "unknown",
                    objectID: object.objectID.uriRepresentation().absoluteString,
                    changeType: object.isInserted ? .insert : .update
                )
            }
        )
    }
    
    private func storeAuditTrail(_ trail: AuditTrail) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(trail)
        let encryptedData = try encrypt(data)
        
        // Store in secure audit log
        try HIPAALogger.shared.logAuditTrail(encryptedData)
    }
}

// MARK: - Types

extension SecureStorageService {
    public enum StorageError: LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case integrityCheckFailed
        case keyStorageFailed
        case accessDenied
        case dataNotFound
        
        public var errorDescription: String? {
            switch self {
            case .encryptionFailed:
                return "Failed to encrypt data"
            case .decryptionFailed:
                return "Failed to decrypt data"
            case .integrityCheckFailed:
                return "Data integrity check failed"
            case .keyStorageFailed:
                return "Failed to store encryption key"
            case .accessDenied:
                return "Access denied"
            case .dataNotFound:
                return "Data not found"
            }
        }
    }
    
    private struct AuditTrail: Codable {
        let timestamp: Date
        let userID: String
        let changes: [Change]
        
        struct Change: Codable {
            let entityName: String
            let objectID: String
            let changeType: ChangeType
        }
        
        enum ChangeType: String, Codable {
            case insert
            case update
            case delete
        }
    }
}