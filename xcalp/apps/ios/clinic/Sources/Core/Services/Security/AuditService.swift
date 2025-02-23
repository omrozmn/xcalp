import Foundation
import CryptoKit
import Dependencies

public final class RealAuditService: AuditService {
    public static let shared: AuditService = RealAuditService()
    
    private let storage: SecureStorageService
    private let encryption: HIPAAEncryptionService
    private let logger: LoggingService
    
    private init() {
        self.storage = SecureStorageService.shared
        self.encryption = HIPAAEncryptionService.shared
        self.logger = LoggingService.shared
    }
    
    public func getAuditTrail(forIdentifier identifier: String, type: DataType) async throws -> AuditTrail {
        // Retrieve encrypted audit data
        let auditData: AuditTrailData = try await storage.retrieve(
            type: .systemConfig,
            identifier: "audit_\(type.rawValue)_\(identifier)"
        )
        
        // Verify audit trail integrity
        let entries = try await validateAndDecryptEntries(auditData.entries)
        
        return AuditTrail(
            entries: entries,
            storageType: .encrypted
        )
    }
    
    public func hasAuditTrail(forIdentifier identifier: String, type: DataType) async throws -> Bool {
        do {
            _ = try await getAuditTrail(forIdentifier: identifier, type: type)
            return true
        } catch StorageError.dataNotFound {
            return false
        }
    }
    
    public func addAuditEntry(
        resourceId: String,
        resourceType: DataType,
        action: AuditActionType,
        userId: String,
        userRole: UserRole,
        accessReason: String
    ) async throws {
        // Get existing audit trail or create new one
        let trail = try await getOrCreateAuditTrail(
            forIdentifier: resourceId,
            type: resourceType
        )
        
        // Create new entry
        let entry = try await createAuditEntry(
            resourceId: resourceId,
            resourceType: resourceType,
            action: action,
            userId: userId,
            userRole: userRole,
            accessReason: accessReason,
            previousHash: trail.lastHash
        )
        
        // Add entry to trail
        var updatedTrail = trail
        updatedTrail.entries.append(entry)
        updatedTrail.lastHash = entry.integrityHash
        
        // Store updated trail
        try await storage.store(
            updatedTrail,
            type: .systemConfig,
            identifier: "audit_\(resourceType.rawValue)_\(resourceId)"
        )
        
        logger.logHIPAAEvent(
            "Audit entry added",
            type: .modification,
            metadata: [
                "resourceId": resourceId,
                "resourceType": resourceType.rawValue,
                "action": action.rawValue,
                "userId": userId
            ]
        )
    }
    
    // MARK: - Private Methods
    
    private func validateAndDecryptEntries(_ entries: [EncryptedAuditEntry]) async throws -> [AuditEntry] {
        var result: [AuditEntry] = []
        var previousHash = Data()
        
        for encryptedEntry in entries {
            // Decrypt entry data
            let decryptedData = try encryption.decrypt(encryptedEntry.encryptedData)
            let entry = try JSONDecoder().decode(AuditEntry.self, from: decryptedData)
            
            // Verify hash chain
            let computedHash = try await computeEntryHash(entry, previousHash: previousHash)
            guard computedHash == entry.integrityHash else {
                throw AuditServiceError.integrityViolation
            }
            
            result.append(entry)
            previousHash = computedHash
        }
        
        return result
    }
    
    private func getOrCreateAuditTrail(forIdentifier identifier: String, type: DataType) async throws -> AuditTrailData {
        do {
            return try await storage.retrieve(
                type: .systemConfig,
                identifier: "audit_\(type.rawValue)_\(identifier)"
            )
        } catch StorageError.dataNotFound {
            return AuditTrailData(entries: [], lastHash: Data())
        }
    }
    
    private func createAuditEntry(
        resourceId: String,
        resourceType: DataType,
        action: AuditActionType,
        userId: String,
        userRole: UserRole,
        accessReason: String,
        previousHash: Data
    ) async throws -> EncryptedAuditEntry {
        let entry = AuditEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            userId: userId,
            userRole: userRole,
            actionType: action,
            resourceType: resourceType.rawValue,
            resourceId: resourceId,
            accessReason: accessReason,
            integrityHash: Data() // Temporary placeholder
        )
        
        // Compute integrity hash
        let hash = try await computeEntryHash(entry, previousHash: previousHash)
        let finalEntry = entry.updateHash(hash)
        
        // Encrypt entry
        let entryData = try JSONEncoder().encode(finalEntry)
        let encrypted = try encryption.encrypt(entryData, type: .systemConfig)
        
        return EncryptedAuditEntry(encryptedData: encrypted)
    }
    
    private func computeEntryHash(_ entry: AuditEntry, previousHash: Data) async throws -> Data {
        let encoder = JSONEncoder()
        var entryData = try encoder.encode(entry)
        entryData.append(previousHash)
        
        let sha256 = SHA256.hash(data: entryData)
        return Data(sha256)
    }
}

// MARK: - Supporting Types

private struct AuditTrailData: Codable {
    var entries: [EncryptedAuditEntry]
    var lastHash: Data
}

private struct EncryptedAuditEntry: Codable {
    let encryptedData: EncryptedData
}

enum AuditServiceError: LocalizedError {
    case integrityViolation
    
    var errorDescription: String? {
        switch self {
        case .integrityViolation:
            return "Audit trail integrity violation detected"
        }
    }
}

extension AuditEntry {
    func updateHash(_ hash: Data) -> AuditEntry {
        return AuditEntry(
            id: id,
            timestamp: timestamp,
            userId: userId,
            userRole: userRole,
            actionType: actionType,
            resourceType: resourceType,
            resourceId: resourceId,
            accessReason: accessReason,
            integrityHash: hash
        )
    }
}

// MARK: - Dependency Interface

private enum AuditServiceKey: DependencyKey {
    static let liveValue: AuditService = RealAuditService.shared
    
    #if DEBUG
    static let testValue: AuditService = MockAuditService.shared
    #endif
}

extension DependencyValues {
    var auditService: AuditService {
        get { self[AuditServiceKey.self] }
        set { self[AuditServiceKey.self] = newValue }
    }
}