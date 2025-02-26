import Foundation
import os.log
import CryptoKit

final class SecureAuditLogger {
    static let shared = SecureAuditLogger()
    
    private let errorHandler = XCErrorHandler.shared
    private let keyManager = KeyManager.shared
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "AuditLog")
    
    private let auditQueue = DispatchQueue(label: "com.xcalp.clinic.audit", qos: .utility)
    
    struct AuditEvent: Codable {
        let timestamp: Date
        let eventType: EventType
        let userId: String
        let actionType: ActionType
        let resourceId: String
        let details: [String: String]
        let deviceInfo: DeviceInfo
        let hashChain: String
        
        enum EventType: String, Codable {
            case clinicalAccess
            case dataExport
            case scanning
            case analysis
            case systemOperation
        }
        
        enum ActionType: String, Codable {
            case create
            case read
            case update
            case delete
            case export
            case share
            case validate
        }
    }
    
    private var previousEventHash: String?
    
    func logEvent(
        type: AuditEvent.EventType,
        action: AuditEvent.ActionType,
        resourceId: String,
        details: [String: String] = [:]
    ) {
        auditQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let event = try self.createAuditEvent(
                    type: type,
                    action: action,
                    resourceId: resourceId,
                    details: details
                )
                
                try self.storeEvent(event)
                self.previousEventHash = try self.calculateEventHash(event)
                
                // Log to system logger for immediate visibility
                self.logger.info("Audit event logged: \(type.rawValue) - \(action.rawValue)")
                
            } catch {
                self.errorHandler.handle(error, severity: .high)
            }
        }
    }
    
    func validateAuditTrail() throws -> Bool {
        let events = try fetchAuditEvents()
        var previousHash: String?
        
        for event in events {
            let calculatedHash = try calculateEventHash(event)
            
            if let previousEventHash = previousHash {
                guard event.hashChain == previousEventHash else {
                    throw AuditError.auditChainCompromised
                }
            }
            
            previousHash = calculatedHash
        }
        
        return true
    }
    
    func exportAuditLog(from: Date, to: Date) throws -> URL {
        let events = try fetchAuditEvents(from: from, to: to)
        let exportData = try JSONEncoder().encode(events)
        
        // Sign the export
        let signature = try signAuditExport(exportData)
        
        // Create export bundle
        let exportBundle = AuditExportBundle(
            events: events,
            signature: signature,
            exportTimestamp: Date(),
            exportedBy: getCurrentUserId()
        )
        
        // Save to temporary file
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let exportURL = temporaryDirectory.appendingPathComponent("audit_log_\(Date().timeIntervalSince1970).json")
        try JSONEncoder().encode(exportBundle).write(to: exportURL)
        
        return exportURL
    }
    
    // MARK: - Private Methods
    private func createAuditEvent(
        type: AuditEvent.EventType,
        action: AuditEvent.ActionType,
        resourceId: String,
        details: [String: String]
    ) throws -> AuditEvent {
        let event = AuditEvent(
            timestamp: Date(),
            eventType: type,
            userId: getCurrentUserId(),
            actionType: action,
            resourceId: resourceId,
            details: details,
            deviceInfo: try getDeviceInfo(),
            hashChain: previousEventHash ?? "initial"
        )
        
        return event
    }
    
    private func calculateEventHash(_ event: AuditEvent) throws -> String {
        let eventData = try JSONEncoder().encode(event)
        let hash = SHA256.hash(data: eventData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func storeEvent(_ event: AuditEvent) throws {
        // Encrypt event data
        let symmetricKey = try keyManager.generateSymmetricKey()
        let eventData = try JSONEncoder().encode(event)
        let sealedBox = try AES.GCM.seal(eventData, using: symmetricKey)
        
        // Store in Core Data
        let context = CoreDataStack.shared.newBackgroundContext()
        
        context.performAndWait {
            let auditEntity = AuditEventEntity(context: context)
            auditEntity.timestamp = event.timestamp
            auditEntity.eventType = event.eventType.rawValue
            auditEntity.encryptedData = sealedBox.combined
            auditEntity.hashChain = event.hashChain
            
            do {
                try context.save()
            } catch {
                self.errorHandler.handle(error, severity: .high)
            }
        }
    }
    
    private func fetchAuditEvents(from: Date? = nil, to: Date? = nil) throws -> [AuditEvent] {
        let context = CoreDataStack.shared.viewContext
        let fetchRequest: NSFetchRequest<AuditEventEntity> = AuditEventEntity.fetchRequest()
        
        // Add date range predicates if provided
        var predicates: [NSPredicate] = []
        if let fromDate = from {
            predicates.append(NSPredicate(format: "timestamp >= %@", fromDate as NSDate))
        }
        if let toDate = to {
            predicates.append(NSPredicate(format: "timestamp <= %@", toDate as NSDate))
        }
        
        if !predicates.isEmpty {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        let entities = try context.fetch(fetchRequest)
        return try entities.compactMap { entity in
            guard let encryptedData = entity.encryptedData else { return nil }
            
            // Decrypt event data
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let symmetricKey = try retrieveSymmetricKey(for: entity.timestamp)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            return try JSONDecoder().decode(AuditEvent.self, from: decryptedData)
        }
    }
    
    private func signAuditExport(_ data: Data) throws -> Data {
        // Sign with app's private key
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            try getPrivateKey(),
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? AuditError.signatureFailed
        }
        
        return signature
    }
    
    private func getPrivateKey() throws -> SecKey {
        // Implementation would retrieve the app's private key from secure storage
        throw AuditError.privateKeyNotAvailable
    }
    
    private func retrieveSymmetricKey(for timestamp: Date) throws -> SymmetricKey {
        // Implementation would retrieve the symmetric key for the specific audit entry
        throw AuditError.symmetricKeyNotFound
    }
    
    private func getDeviceInfo() throws -> DeviceInfo {
        return DeviceInfo(
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )
    }
    
    private func getCurrentUserId() -> String {
        // Implementation would get the current authenticated user's ID
        return "current_user_id"
    }
}

struct AuditExportBundle: Codable {
    let events: [AuditEvent]
    let signature: Data
    let exportTimestamp: Date
    let exportedBy: String
}

enum AuditError: Error {
    case auditChainCompromised
    case signatureFailed
    case privateKeyNotAvailable
    case symmetricKeyNotFound
    case storageError
    case exportError
}