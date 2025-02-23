import Foundation

extension AuditLogCheck {
    func validate<T: HIPAACompliant>(_ data: T) async throws {
        // Get audit trail
        let auditService = AuditService.shared
        let auditTrail = try await auditService.getAuditTrail(
            forIdentifier: data.identifier,
            type: T.dataType
        )
        
        // Check audit trail completeness
        try validateAuditCompleteness(auditTrail)
        
        // Verify audit integrity
        try await validateAuditIntegrity(auditTrail)
        
        // Check audit retention
        try validateAuditRetention(auditTrail)
        
        // Verify required fields
        try validateRequiredFields(auditTrail)
        
        LoggingService.shared.logHIPAAEvent(
            "Audit log validation successful",
            type: .access,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "entryCount": auditTrail.entries.count,
                "timespan": auditTrail.timespan
            ]
        )
    }
    
    private func validateAuditCompleteness(_ trail: AuditTrail) throws {
        // Check for gaps in audit timeline
        let sortedEntries = trail.entries.sorted { $0.timestamp < $1.timestamp }
        guard !sortedEntries.isEmpty else {
            throw AuditError.emptyAuditTrail
        }
        
        // Check for suspicious gaps (more than 24 hours between entries)
        for i in 0..<(sortedEntries.count - 1) {
            let gap = sortedEntries[i + 1].timestamp.timeIntervalSince(sortedEntries[i].timestamp)
            if gap > 24 * 3600 {
                throw AuditError.suspiciousGap(
                    start: sortedEntries[i].timestamp,
                    end: sortedEntries[i + 1].timestamp
                )
            }
        }
        
        // Verify all access types are logged
        let accessTypes = Set(sortedEntries.map { $0.actionType })
        let requiredTypes: Set<AuditActionType> = [.view, .modify, .delete]
        let missingTypes = requiredTypes.subtracting(accessTypes)
        
        if !missingTypes.isEmpty {
            throw AuditError.missingActionTypes(Array(missingTypes))
        }
    }
    
    private func validateAuditIntegrity(_ trail: AuditTrail) async throws {
        // Verify hash chain integrity
        var previousHash = Data()
        for entry in trail.entries {
            let computedHash = try await computeEntryHash(entry, previousHash: previousHash)
            guard computedHash == entry.integrityHash else {
                throw AuditError.integrityViolation(entry.id)
            }
            previousHash = computedHash
        }
    }
    
    private func validateAuditRetention(_ trail: AuditTrail) throws {
        let calendar = Calendar.current
        let now = Date()
        
        // HIPAA requires audit logs to be retained for 6 years
        let requiredRetention = calendar.date(byAdding: .year, value: -6, to: now)!
        
        // Check if we have entries covering the required retention period
        guard let oldestEntry = trail.entries.map({ $0.timestamp }).min(),
              oldestEntry <= requiredRetention else {
            throw AuditError.insufficientRetention
        }
        
        // Check if audit storage is secure
        guard trail.storageType == .encrypted else {
            throw AuditError.insecureStorage
        }
    }
    
    private func validateRequiredFields(_ trail: AuditTrail) throws {
        for entry in trail.entries {
            // Check required HIPAA fields
            guard !entry.userId.isEmpty,
                  !entry.actionType.rawValue.isEmpty,
                  !entry.resourceType.isEmpty,
                  entry.timestamp <= Date(),
                  !entry.resourceId.isEmpty else {
                throw AuditError.missingRequiredFields(entry.id)
            }
            
            // Validate user information
            guard entry.userRole != .unknown else {
                throw AuditError.invalidUserRole(entry.id)
            }
            
            // Validate reason for access
            if entry.actionType == .view || entry.actionType == .modify {
                guard !entry.accessReason.isEmpty else {
                    throw AuditError.missingAccessReason(entry.id)
                }
            }
        }
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

struct AuditTrail {
    let entries: [AuditEntry]
    let storageType: AuditStorageType
    
    var timespan: TimeInterval {
        guard let oldest = entries.map({ $0.timestamp }).min(),
              let newest = entries.map({ $0.timestamp }).max() else {
            return 0
        }
        return newest.timeIntervalSince(oldest)
    }
}

struct AuditEntry: Codable {
    let id: String
    let timestamp: Date
    let userId: String
    let userRole: UserRole
    let actionType: AuditActionType
    let resourceType: String
    let resourceId: String
    let accessReason: String
    let integrityHash: Data
}

enum AuditStorageType {
    case encrypted
    case unencrypted
}

enum AuditActionType: String, Codable {
    case view
    case modify
    case delete
}

enum UserRole: String, Codable {
    case admin
    case doctor
    case nurse
    case staff
    case unknown
}

enum AuditError: LocalizedError {
    case emptyAuditTrail
    case suspiciousGap(start: Date, end: Date)
    case missingActionTypes([AuditActionType])
    case integrityViolation(String)
    case insufficientRetention
    case insecureStorage
    case missingRequiredFields(String)
    case invalidUserRole(String)
    case missingAccessReason(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyAuditTrail:
            return "Empty audit trail detected"
        case .suspiciousGap(let start, let end):
            return "Suspicious gap in audit trail between \(start) and \(end)"
        case .missingActionTypes(let types):
            return "Missing required action types in audit trail: \(types.map { $0.rawValue }.joined(separator: ", "))"
        case .integrityViolation(let entryId):
            return "Audit trail integrity violation detected for entry: \(entryId)"
        case .insufficientRetention:
            return "Audit trail retention period insufficient"
        case .insecureStorage:
            return "Audit trail storage is not encrypted"
        case .missingRequiredFields(let entryId):
            return "Missing required fields in audit entry: \(entryId)"
        case .invalidUserRole(let entryId):
            return "Invalid user role in audit entry: \(entryId)"
        case .missingAccessReason(let entryId):
            return "Missing access reason in audit entry: \(entryId)"
        }
    }
}

// MARK: - Audit Service Interface

protocol AuditService {
    static var shared: AuditService { get }
    func getAuditTrail(forIdentifier: String, type: DataType) async throws -> AuditTrail
    func hasAuditTrail(forIdentifier: String, type: DataType) async throws -> Bool
}

#if DEBUG
// Mock implementation for testing
class MockAuditService: AuditService {
    static let shared: AuditService = MockAuditService()
    
    func getAuditTrail(forIdentifier: String, type: DataType) async throws -> AuditTrail {
        return AuditTrail(
            entries: [],
            storageType: .encrypted
        )
    }
    
    func hasAuditTrail(forIdentifier: String, type: DataType) async throws -> Bool {
        return true
    }
}
#endif