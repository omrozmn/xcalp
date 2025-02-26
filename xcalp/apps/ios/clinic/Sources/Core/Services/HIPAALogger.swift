import Foundation
import OSLog

public actor HIPAALogger {
    public static let shared = HIPAALogger()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "HIPAA")
    private let auditStore: HIPAAAuditStore
    
    private init(auditStore: HIPAAAuditStore = .shared) {
        self.auditStore = auditStore
    }
    
    public func log(
        event: Event,
        details: [String: Any],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        let entry = LogEntry(
            timestamp: Date(),
            event: event,
            userID: SessionManager.shared.currentUser?.id ?? "unknown",
            details: details,
            source: SourceLocation(file: file, function: function, line: line)
        )
        
        // Log to system
        logger.log(level: .info, "\(entry.description)")
        
        // Store in audit trail
        await auditStore.store(entry)
        
        // Check for security-sensitive events
        if event.isSecuritySensitive {
            await SecurityMonitor.shared.analyzeEvent(entry)
        }
    }
    
    public func logAuditTrail(_ encryptedData: Data) throws {
        try auditStore.storeEncryptedAuditTrail(encryptedData)
    }
    
    public func generateAuditReport(
        from startDate: Date,
        to endDate: Date
    ) async throws -> AuditReport {
        return try await auditStore.generateReport(from: startDate, to: endDate)
    }
    
    public func verifyAuditTrailIntegrity() async throws {
        try await auditStore.verifyIntegrity()
    }
}

extension HIPAALogger {
    public struct Event: Equatable, Codable {
        public let name: String
        public let isSecuritySensitive: Bool
        
        public init(name: String, isSecuritySensitive: Bool = false) {
            self.name = name
            self.isSecuritySensitive = isSecuritySensitive
        }
    }
    
    struct LogEntry: Codable {
        let id: UUID
        let timestamp: Date
        let event: Event
        let userID: String
        let details: [String: Any]
        let source: SourceLocation
        
        init(
            timestamp: Date,
            event: Event,
            userID: String,
            details: [String: Any],
            source: SourceLocation
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.event = event
            self.userID = userID
            self.details = details
            self.source = source
        }
        
        var description: String {
            """
            HIPAA Event: \(event.name)
            Time: \(timestamp)
            User: \(userID)
            Details: \(details)
            Source: \(source)
            """
        }
    }
    
    struct SourceLocation: Codable {
        let file: String
        let function: String
        let line: Int
    }
    
    struct AuditReport: Codable {
        let startDate: Date
        let endDate: Date
        let entries: [LogEntry]
        let summary: Summary
        
        struct Summary: Codable {
            let totalEvents: Int
            let securityEvents: Int
            let uniqueUsers: Int
            let eventTypes: [String: Int]
        }
    }
}

actor HIPAAAuditStore {
    static let shared = HIPAAAuditStore()
    
    private let fileManager: FileManager
    private let encryptionService: EncryptionService
    
    private init(
        fileManager: FileManager = .default,
        encryptionService: EncryptionService = .shared
    ) {
        self.fileManager = fileManager
        self.encryptionService = encryptionService
        setupAuditDirectory()
    }
    
    func store(_ entry: HIPAALogger.LogEntry) async {
        do {
            let data = try JSONEncoder().encode(entry)
            let encryptedData = try encryptionService.encrypt(data)
            try storeEncryptedAuditTrail(encryptedData)
        } catch {
            logger.error("Failed to store audit entry: \(error.localizedDescription)")
        }
    }
    
    func storeEncryptedAuditTrail(_ encryptedData: Data) throws {
        let filename = "\(Date().timeIntervalSince1970)-\(UUID()).audit"
        let url = auditDirectory.appendingPathComponent(filename)
        try encryptedData.write(to: url)
    }
    
    func generateReport(
        from startDate: Date,
        to endDate: Date
    ) async throws -> HIPAALogger.AuditReport {
        let entries = try await loadEntries(from: startDate, to: endDate)
        
        let uniqueUsers = Set(entries.map(\.userID)).count
        var eventCounts: [String: Int] = [:]
        var securityEvents = 0
        
        entries.forEach { entry in
            eventCounts[entry.event.name, default: 0] += 1
            if entry.event.isSecuritySensitive {
                securityEvents += 1
            }
        }
        
        return HIPAALogger.AuditReport(
            startDate: startDate,
            endDate: endDate,
            entries: entries,
            summary: .init(
                totalEvents: entries.count,
                securityEvents: securityEvents,
                uniqueUsers: uniqueUsers,
                eventTypes: eventCounts
            )
        )
    }
    
    func verifyIntegrity() async throws {
        let files = try fileManager.contentsOfDirectory(
            at: auditDirectory,
            includingPropertiesForKeys: nil
        )
        
        for file in files {
            let encryptedData = try Data(contentsOf: file)
            _ = try encryptionService.decrypt(encryptedData)
        }
    }
    
    private func loadEntries(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HIPAALogger.LogEntry] {
        let files = try fileManager.contentsOfDirectory(
            at: auditDirectory,
            includingPropertiesForKeys: nil
        )
        
        return try await withThrowingTaskGroup(
            of: [HIPAALogger.LogEntry].self
        ) { group in
            for file in files {
                group.addTask {
                    let encryptedData = try Data(contentsOf: file)
                    let data = try self.encryptionService.decrypt(encryptedData)
                    let entries = try JSONDecoder().decode([HIPAALogger.LogEntry].self, from: data)
                    return entries.filter { entry in
                        (startDate...endDate).contains(entry.timestamp)
                    }
                }
            }
            
            var allEntries: [HIPAALogger.LogEntry] = []
            for try await entries in group {
                allEntries.append(contentsOf: entries)
            }
            
            return allEntries.sorted { $0.timestamp < $1.timestamp }
        }
    }
    
    private var auditDirectory: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HIPAAAudit", isDirectory: true)
        
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        return url
    }
    
    private func setupAuditDirectory() {
        let url = auditDirectory
        let path = url.path
        
        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )
        }
        
        // Set file protection
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }
}