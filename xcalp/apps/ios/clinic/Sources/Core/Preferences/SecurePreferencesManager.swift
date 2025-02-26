import Foundation

actor SecurePreferencesManager {
    static let shared = SecurePreferencesManager()
    
    private let storage = SecureStorage.shared
    private let regionManager = RegionalComplianceManager.shared
    private let analytics = AnalyticsService.shared
    
    private var cache: [String: Any] = [:]
    private let preferencesQueue = DispatchQueue(label: "com.xcalp.clinic.preferences", qos: .userInitiated)
    
    private init() {
        loadPreferences()
    }
    
    // MARK: - Public Interface
    
    func setPreference(_ value: Any, forKey key: PreferenceKey) async throws {
        let region = regionManager.getCurrentRegion()
        
        // Validate preference against regional rules
        try validatePreference(value, forKey: key, in: region)
        
        // Store with regional context
        let contextKey = contextualize(key, for: region)
        try await storePreference(value, forKey: contextKey)
        
        // Update cache
        updateCache(value, forKey: contextKey)
        
        // Track preference change
        trackPreferenceUpdate(key: key, region: region)
    }
    
    func getPreference<T>(_ key: PreferenceKey) async throws -> T? {
        let region = regionManager.getCurrentRegion()
        let contextKey = contextualize(key, for: region)
        
        // Check cache first
        if let cached = cache[contextKey] as? T {
            return cached
        }
        
        // Load from secure storage
        return try await loadPreference(forKey: contextKey)
    }
    
    func getCulturalPreferences() async throws -> CulturalPreferences {
        let region = regionManager.getCurrentRegion()
        let key = "cultural_preferences_\(region.rawValue)"
        
        if let cached = cache[key] as? CulturalPreferences {
            return cached
        }
        
        return try await loadPreference(forKey: key) ?? .defaultFor(region)
    }
    
    func migratePreferences(from sourceRegion: Region, to targetRegion: Region) async throws {
        let preferences = try await getAllPreferences(for: sourceRegion)
        
        for (key, value) in preferences {
            if let adaptedValue = try await adaptPreference(
                value,
                forKey: key,
                from: sourceRegion,
                to: targetRegion
            ) {
                let newKey = contextualize(key, for: targetRegion)
                try await storePreference(adaptedValue, forKey: newKey)
            }
        }
        
        // Track migration
        analytics.trackEvent(
            category: .preferences,
            action: "migration",
            label: "\(sourceRegion.rawValue)_to_\(targetRegion.rawValue)",
            value: preferences.count,
            metadata: [:]
        )
    }
    
    func clearPreferences(olderThan date: Date? = nil) async throws {
        let region = regionManager.getCurrentRegion()
        
        if let date = date {
            try await clearOutdatedPreferences(before: date, in: region)
        } else {
            try await clearAllPreferences(in: region)
        }
        
        // Clear cache
        cache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func loadPreferences() {
        Task {
            do {
                let region = regionManager.getCurrentRegion()
                let preferences = try await getAllPreferences(for: region)
                
                preferencesQueue.async {
                    self.cache = preferences
                }
            } catch {
                Logger.shared.error("Failed to load preferences: \(error.localizedDescription)")
            }
        }
    }
    
    private func validatePreference(_ value: Any, forKey key: PreferenceKey, in region: Region) throws {
        switch key {
        case .culturalPreferences:
            guard value is CulturalPreferences else {
                throw PreferenceError.invalidType(expected: "CulturalPreferences")
            }
            
        case .measurementSystem:
            guard let system = value as? MeasurementSystem,
                  isValidMeasurementSystem(system, for: region) else {
                throw PreferenceError.invalidValue("Unsupported measurement system for region")
            }
            
        case .language:
            guard let language = value as? String,
                  isSupportedLanguage(language, in: region) else {
                throw PreferenceError.invalidValue("Unsupported language for region")
            }
            
        case .notifications:
            guard let settings = value as? NotificationPreferences,
                  isCompliantNotificationSettings(settings, in: region) else {
                throw PreferenceError.invalidValue("Non-compliant notification settings")
            }
        }
    }
    
    private func contextualize(_ key: PreferenceKey, for region: Region) -> String {
        return "\(key.rawValue)_\(region.rawValue)"
    }
    
    private func storePreference(_ value: Any, forKey key: String) async throws {
        let data = try JSONEncoder().encode(PreferenceWrapper(value: value))
        try await storage.store(data, forKey: key, expires: .never)
    }
    
    private func loadPreference<T>(forKey key: String) async throws -> T? {
        guard let data: Data = try await storage.retrieve(Data.self, forKey: key),
              let wrapper = try? JSONDecoder().decode(PreferenceWrapper.self, from: data),
              let value = wrapper.value as? T else {
            return nil
        }
        return value
    }
    
    private func updateCache(_ value: Any, forKey key: String) {
        preferencesQueue.async {
            self.cache[key] = value
        }
    }
    
    private func getAllPreferences(for region: Region) async throws -> [String: Any] {
        // Implementation would retrieve all preferences for given region
        return [:]
    }
    
    private func adaptPreference(
        _ value: Any,
        forKey key: PreferenceKey,
        from sourceRegion: Region,
        to targetRegion: Region
    ) async throws -> Any? {
        // Implementation would adapt preference values between regions
        return value
    }
    
    private func trackPreferenceUpdate(key: PreferenceKey, region: Region) {
        analytics.trackEvent(
            category: .preferences,
            action: "update",
            label: key.rawValue,
            value: 1,
            metadata: ["region": region.rawValue]
        )
    }
}

// MARK: - Supporting Types

enum PreferenceKey: String {
    case culturalPreferences
    case measurementSystem
    case language
    case notifications
    case accessibility
    case privacy
    case workflow
}

struct PreferenceWrapper: Codable {
    let value: Any
    
    private enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    init(value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(describing: type(of: value)), forKey: .type)
        
        if let encodable = value as? Encodable {
            try encodable.encode(to: encoder)
        } else {
            throw PreferenceError.encodingFailed
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case String(describing: CulturalPreferences.self):
            value = try CulturalPreferences(from: decoder)
        case String(describing: MeasurementSystem.self):
            value = try MeasurementSystem(from: decoder)
        case String(describing: NotificationPreferences.self):
            value = try NotificationPreferences(from: decoder)
        default:
            throw PreferenceError.decodingFailed
        }
    }
}

enum PreferenceError: LocalizedError {
    case invalidType(expected: String)
    case invalidValue(String)
    case encodingFailed
    case decodingFailed
    case migrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidType(let expected):
            return "Invalid preference type, expected: \(expected)"
        case .invalidValue(let reason):
            return "Invalid preference value: \(reason)"
        case .encodingFailed:
            return "Failed to encode preference"
        case .decodingFailed:
            return "Failed to decode preference"
        case .migrationFailed(let reason):
            return "Preference migration failed: \(reason)"
        }
    }
}

struct NotificationPreferences: Codable {
    var enabled: Bool
    var types: Set<NotificationType>
    var quietHours: DateInterval?
    var culturalConsiderations: Set<String>
    
    enum NotificationType: String, Codable {
        case workflow
        case reminders
        case updates
        case marketing
    }
}

extension CulturalPreferences {
    static func defaultFor(_ region: Region) -> CulturalPreferences {
        // Implementation would provide region-specific defaults
        return CulturalPreferences(
            preferredDensity: 80.0,
            traditionalStyles: [],
            ageSpecificPatterns: false,
            religionConsiderations: []
        )
    }
}