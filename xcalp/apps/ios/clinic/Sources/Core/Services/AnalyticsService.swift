import Foundation

public actor AnalyticsService {
    public static let shared = AnalyticsService()
    
    private let hipaaLogger: HIPAALogger
    private let secureStorage: SecureStorageService
    private var eventBuffer: [AnalyticsEvent] = []
    private let bufferLimit = 100
    private var backgroundTask: Task<Void, Never>?
    
    private init(
        hipaaLogger: HIPAALogger = .shared,
        secureStorage: SecureStorageService = .shared
    ) {
        self.hipaaLogger = hipaaLogger
        self.secureStorage = secureStorage
        startPeriodicFlush()
    }
    
    public func track(
        event: Event,
        properties: [String: Any] = [:],
        userId: String? = nil
    ) {
        let analyticsEvent = AnalyticsEvent(
            name: event.name,
            properties: sanitizeProperties(properties),
            userId: userId ?? SessionManager.shared.currentUser?.id,
            timestamp: Date()
        )
        
        eventBuffer.append(analyticsEvent)
        
        if eventBuffer.count >= bufferLimit {
            Task {
                await flushEvents()
            }
        }
    }
    
    public func track(
        error: Error,
        severity: ErrorSeverity,
        context: [String: Any] = [:]
    ) {
        var properties = context
        properties["error_description"] = error.localizedDescription
        properties["error_type"] = String(describing: type(of: error))
        properties["severity"] = severity.rawValue
        
        track(
            event: .error,
            properties: properties
        )
    }
    
    private func startPeriodicFlush() {
        backgroundTask?.cancel()
        backgroundTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                await flushEvents()
            }
        }
    }
    
    private func flushEvents() async {
        guard !eventBuffer.isEmpty else { return }
        
        let events = eventBuffer
        eventBuffer.removeAll()
        
        do {
            // Encrypt events before storage
            let eventsData = try JSONEncoder().encode(events)
            let encryptedData = try await secureStorage.performSecureOperation {
                try EncryptionService.shared.encrypt(eventsData)
            }
            
            // Store encrypted events
            try await storeEvents(encryptedData)
            
            // Log successful analytics storage
            await hipaaLogger.log(
                event: .analyticsStored,
                details: [
                    "eventCount": events.count,
                    "timestamp": Date()
                ]
            )
        } catch {
            // Log failure and restore events to buffer
            eventBuffer.insert(contentsOf: events, at: 0)
            
            await hipaaLogger.log(
                event: .analyticsStorageFailed,
                details: [
                    "error": error.localizedDescription,
                    "eventCount": events.count
                ]
            )
        }
    }
    
    private func storeEvents(_ encryptedData: Data) async throws {
        let filename = "\(Date().timeIntervalSince1970)-\(UUID()).analytics"
        let analyticsDirectory = try getAnalyticsDirectory()
        let fileURL = analyticsDirectory.appendingPathComponent(filename)
        
        try encryptedData.write(to: fileURL)
    }
    
    private func getAnalyticsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let analyticsDir = appSupport.appendingPathComponent("Analytics", isDirectory: true)
        
        if !fileManager.fileExists(atPath: analyticsDir.path) {
            try fileManager.createDirectory(
                at: analyticsDir,
                withIntermediateDirectories: true,
                attributes: [
                    FileAttributeKey.protectionKey: FileProtectionType.complete
                ]
            )
        }
        
        return analyticsDir
    }
    
    private func sanitizeProperties(_ properties: [String: Any]) -> [String: Any] {
        var sanitized = [String: Any]()
        
        for (key, value) in properties {
            // Remove any potential PHI or sensitive data
            if !isPropertySafe(key, value) {
                continue
            }
            
            sanitized[key] = value
        }
        
        return sanitized
    }
    
    private func isPropertySafe(_ key: String, _ value: Any) -> Bool {
        let sensitiveKeys = [
            "ssn", "social", "dob", "birth", "address", "phone", "email",
            "medical", "health", "diagnosis", "treatment", "prescription"
        ]
        
        // Check for sensitive keys
        let lowercaseKey = key.lowercased()
        if sensitiveKeys.contains(where: { lowercaseKey.contains($0) }) {
            return false
        }
        
        // Check value patterns (e.g., SSN, phone numbers, etc.)
        if let stringValue = value as? String {
            // SSN pattern
            if stringValue.range(of: #"^\d{3}-?\d{2}-?\d{4}$"#, options: .regularExpression) != nil {
                return false
            }
            
            // Phone pattern
            if stringValue.range(of: #"^\+?1?\d{10}$"#, options: .regularExpression) != nil {
                return false
            }
            
            // Email pattern
            if stringValue.range(of: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#, options: .regularExpression) != nil {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Types

extension AnalyticsService {
    public struct Event {
        public let name: String
        
        public init(name: String) {
            self.name = name
        }
        
        static let error = Event(name: "error")
    }
    
    private struct AnalyticsEvent: Codable {
        let id: UUID = UUID()
        let name: String
        let properties: [String: Any]
        let userId: String?
        let timestamp: Date
        
        enum CodingKeys: String, CodingKey {
            case id, name, properties, userId, timestamp
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(properties.jsonString, forKey: .properties)
            try container.encode(userId, forKey: .userId)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
    
    public enum ErrorSeverity: String {
        case critical
        case high
        case medium
        case low
    }
}

extension Dictionary where Key == String, Value == Any {
    var jsonString: String {
        if let data = try? JSONSerialization.data(withJSONObject: self),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}

extension HIPAALogger.Event {
    static let analyticsStored = HIPAALogger.Event(name: "analytics_stored")
    static let analyticsStorageFailed = HIPAALogger.Event(name: "analytics_storage_failed")
}