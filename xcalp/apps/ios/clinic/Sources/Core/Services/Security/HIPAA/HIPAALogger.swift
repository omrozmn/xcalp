import CryptoKit
import Foundation
import Logging

/// HIPAA-compliant audit logging system
public final class HIPAALogger {
    public static let shared = HIPAALogger()
    
    private let logger = Logger(label: "com.xcalp.clinic.hipaa")
    private let dateFormatter: ISO8601DateFormatter
    private let queue: DispatchQueue
    
    private init() {
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.queue = DispatchQueue(label: "com.xcalp.clinic.hipaa.logging", qos: .utility)
    }
    
    /// Log a HIPAA-relevant event
    /// - Parameters:
    ///   - type: Type of event
    ///   - action: Action being performed
    ///   - userID: ID of user performing action
    ///   - details: Additional event details
    public func log(type: EventType, action: String, userID: String, details: String? = nil) {
        queue.async {
            let event = AuditEvent(
                timestamp: self.dateFormatter.string(from: Date()),
                type: type,
                action: action,
                userID: userID,
                details: details
            )
            
            self.logEvent(event)
            self.storeEvent(event)
        }
    }
    
    /// Export audit logs for compliance review
    /// - Parameter timeRange: Optional time range to export
    /// - Returns: Encrypted audit log data
    public func exportLogs(timeRange: DateInterval? = nil) throws -> Data {
        let logs = try loadStoredEvents(in: timeRange)
        let jsonData = try JSONEncoder().encode(logs)
        return try HIPAACompliance.shared.encryptData(jsonData)
    }
    
    // MARK: - Private Methods
    
    private func logEvent(_ event: AuditEvent) {
        let metadata: Logger.Metadata = [
            "type": .string(event.type.rawValue),
            "action": .string(event.action),
            "userID": .string(event.userID),
            "details": .string(event.details ?? "N/A")
        ]
        
        logger.info("HIPAA Event", metadata: metadata)
    }
    
    private func storeEvent(_ event: AuditEvent) {
        // Store in secure, encrypted file
        guard let url = getAuditFileURL() else { return }
        
        do {
            let eventData = try JSONEncoder().encode(event)
            let encryptedData = try HIPAACompliance.shared.encryptData(eventData)
            
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(encryptedData)
                handle.write("\n".data(using: .utf8)!)
                try handle.close()
            } else {
                try encryptedData.write(to: url, options: .completeFileProtection)
            }
        } catch {
            logger.error("Failed to store audit event: \(error)")
        }
    }
    
    private func loadStoredEvents(in timeRange: DateInterval? = nil) throws -> [AuditEvent] {
        guard let url = getAuditFileURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        let data = try Data(contentsOf: url)
        let lines = data.split(separator: UInt8(ascii: "\n"))
        
        return try lines.compactMap { line in
            let decryptedData = try HIPAACompliance.shared.decryptData(Data(line))
            let event = try JSONDecoder().decode(AuditEvent.self, from: decryptedData)
            
            if let range = timeRange {
                let timestamp = dateFormatter.date(from: event.timestamp)!
                return range.contains(timestamp) ? event : nil
            }
            
            return event
        }
    }
    
    private func getAuditFileURL() -> URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths.first?.appendingPathComponent("hipaa_audit.log")
    }
}

// MARK: - Supporting Types
extension HIPAALogger {
    public struct AuditEvent: Codable {
        let timestamp: String
        let type: EventType
        let action: String
        let userID: String
        let details: String?
    }
    
    public enum EventType: String, Codable {
        case authentication = "AUTH"
        case dataAccess = "ACCESS"
        case dataModification = "MODIFY"
        case export = "EXPORT"
        case systemError = "ERROR"
        case security = "SECURITY"
    }
}
