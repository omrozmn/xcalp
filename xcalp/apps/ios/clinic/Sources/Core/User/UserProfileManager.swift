import Foundation

actor UserProfileManager {
    static let shared = UserProfileManager()
    
    private let storage = SecureStorage.shared
    private let preferences = SecurePreferencesManager.shared
    private let analytics = AnalyticsService.shared
    private let regionManager = RegionalComplianceManager.shared
    
    private var activeProfiles: [UUID: UserProfile] = [:]
    private let profileQueue = DispatchQueue(label: "com.xcalp.clinic.profiles", qos: .userInitiated)
    
    private init() {
        loadCachedProfiles()
    }
    
    func createProfile(
        for user: User,
        culturalPreferences: CulturalPreferences? = nil
    ) async throws -> UserProfile {
        let region = regionManager.getCurrentRegion()
        
        // Create profile with regional defaults
        var profile = UserProfile(
            id: UUID(),
            userId: user.id,
            region: region,
            createdAt: Date(),
            preferences: culturalPreferences ?? await preferences.getCulturalPreferences()
        )
        
        // Add region-specific customizations
        profile = try await customizeProfile(profile, for: region)
        
        // Store profile
        try await storeProfile(profile)
        
        // Cache profile
        cacheProfile(profile)
        
        // Track creation
        trackProfileEvent("creation", profile: profile)
        
        return profile
    }
    
    func updateProfile(_ profile: UserProfile) async throws {
        let region = regionManager.getCurrentRegion()
        
        // Validate updates
        try validateProfileUpdates(profile, in: region)
        
        // Apply regional adaptations if needed
        let adaptedProfile = try await adaptProfile(profile, to: region)
        
        // Store updated profile
        try await storeProfile(adaptedProfile)
        
        // Update cache
        cacheProfile(adaptedProfile)
        
        // Track update
        trackProfileEvent("update", profile: adaptedProfile)
    }
    
    func getProfile(forUser userId: UUID) async throws -> UserProfile? {
        // Check cache first
        if let cached = activeProfiles[userId] {
            return cached
        }
        
        // Load from storage
        guard let profile: UserProfile = try await storage.retrieve(
            UserProfile.self,
            forKey: "profile_\(userId.uuidString)"
        ) else {
            return nil
        }
        
        // Cache loaded profile
        cacheProfile(profile)
        
        return profile
    }
    
    func migrateProfile(
        _ profile: UserProfile,
        to targetRegion: Region
    ) async throws -> UserProfile {
        // Validate migration possibility
        try validateMigration(from: profile.region, to: targetRegion)
        
        // Create migration record
        let migration = ProfileMigration(
            id: UUID(),
            sourceRegion: profile.region,
            targetRegion: targetRegion,
            timestamp: Date()
        )
        
        // Adapt profile for target region
        var migratedProfile = try await adaptProfile(profile, to: targetRegion)
        migratedProfile.migrations.append(migration)
        
        // Migrate preferences
        try await preferences.migratePreferences(
            from: profile.region,
            to: targetRegion
        )
        
        // Store migrated profile
        try await storeProfile(migratedProfile)
        
        // Update cache
        cacheProfile(migratedProfile)
        
        // Track migration
        trackProfileMigration(migration)
        
        return migratedProfile
    }
    
    // MARK: - Private Methods
    
    private func loadCachedProfiles() {
        Task {
            do {
                let profiles: [UserProfile] = try await storage.retrieve([UserProfile].self, forKey: "cached_profiles") ?? []
                
                profileQueue.async {
                    for profile in profiles {
                        self.activeProfiles[profile.userId] = profile
                    }
                }
            } catch {
                Logger.shared.error("Failed to load cached profiles: \(error.localizedDescription)")
            }
        }
    }
    
    private func customizeProfile(_ profile: UserProfile, for region: Region) async throws -> UserProfile {
        var customized = profile
        
        // Add region-specific settings
        customized.settings = try await getRegionalSettings(for: region)
        
        // Add cultural adaptations
        customized.culturalAdaptations = getCulturalAdaptations(for: region)
        
        return customized
    }
    
    private func validateProfileUpdates(_ profile: UserProfile, in region: Region) throws {
        // Validate against regional requirements
        guard let requirements = getRegionalRequirements(for: region) else {
            throw ProfileError.missingRegionalRequirements(region)
        }
        
        // Check required fields
        for field in requirements.requiredFields {
            guard profile.hasField(field) else {
                throw ProfileError.missingRequiredField(field)
            }
        }
        
        // Validate cultural preferences
        if let culturalPreferences = profile.preferences {
            guard requirements.supportedStyles.isSuperset(of: culturalPreferences.traditionalStyles) else {
                throw ProfileError.unsupportedTraditionalStyles
            }
        }
    }
    
    private func validateMigration(from source: Region, to target: Region) throws {
        // Check if migration path is supported
        guard isSupportedMigrationPath(from: source, to: target) else {
            throw ProfileError.unsupportedMigrationPath(source, target)
        }
        
        // Check if target region is ready
        guard isRegionReady(target) else {
            throw ProfileError.targetRegionNotReady(target)
        }
    }
    
    private func adaptProfile(_ profile: UserProfile, to region: Region) async throws -> UserProfile {
        var adapted = profile
        adapted.region = region
        
        // Adapt measurements if needed
        if let settings = try await getRegionalSettings(for: region) {
            adapted.measurements = try await adaptMeasurements(
                profile.measurements,
                to: settings.measurementSystem
            )
        }
        
        // Adapt cultural preferences
        if let preferences = profile.preferences {
            adapted.preferences = try await adaptCulturalPreferences(
                preferences,
                to: region
            )
        }
        
        return adapted
    }
    
    private func storeProfile(_ profile: UserProfile) async throws {
        try await storage.store(
            profile,
            forKey: "profile_\(profile.userId.uuidString)",
            expires: .never
        )
    }
    
    private func cacheProfile(_ profile: UserProfile) {
        profileQueue.async {
            self.activeProfiles[profile.userId] = profile
        }
    }
    
    private func trackProfileEvent(_ event: String, profile: UserProfile) {
        analytics.trackEvent(
            category: .profiles,
            action: event,
            label: profile.region.rawValue,
            value: 1,
            metadata: [
                "user_id": profile.userId.uuidString,
                "region": profile.region.rawValue
            ]
        )
    }
    
    private func trackProfileMigration(_ migration: ProfileMigration) {
        analytics.trackEvent(
            category: .profiles,
            action: "migration",
            label: "\(migration.sourceRegion.rawValue)_to_\(migration.targetRegion.rawValue)",
            value: 1,
            metadata: [
                "migration_id": migration.id.uuidString,
                "timestamp": String(migration.timestamp.timeIntervalSince1970)
            ]
        )
    }
}

// MARK: - Supporting Types

struct UserProfile: Codable {
    let id: UUID
    let userId: UUID
    var region: Region
    let createdAt: Date
    var updatedAt: Date
    var preferences: CulturalPreferences?
    var settings: RegionalSettings?
    var measurements: [String: Measurement]
    var culturalAdaptations: [CulturalAdaptation]
    var migrations: [ProfileMigration]
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        region: Region,
        createdAt: Date = Date(),
        preferences: CulturalPreferences? = nil
    ) {
        self.id = id
        self.userId = userId
        self.region = region
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.preferences = preferences
        self.measurements = [:]
        self.culturalAdaptations = []
        self.migrations = []
    }
    
    func hasField(_ field: String) -> Bool {
        // Implementation would check for required field presence
        return true
    }
}

struct ProfileMigration: Codable {
    let id: UUID
    let sourceRegion: Region
    let targetRegion: Region
    let timestamp: Date
}

struct RegionalSettings: Codable {
    let measurementSystem: MeasurementSystem
    let dateFormat: String
    let timeFormat: String
    let requiredFields: Set<String>
    let supportedStyles: Set<TraditionalStyle>
}

struct Measurement: Codable {
    let value: Double
    let unit: String
    let timestamp: Date
}

enum ProfileError: LocalizedError {
    case missingRegionalRequirements(Region)
    case missingRequiredField(String)
    case unsupportedTraditionalStyles
    case unsupportedMigrationPath(Region, Region)
    case targetRegionNotReady(Region)
    case adaptationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRegionalRequirements(let region):
            return "Missing regional requirements for \(region)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .unsupportedTraditionalStyles:
            return "One or more traditional styles are not supported in this region"
        case .unsupportedMigrationPath(let source, let target):
            return "Migration not supported from \(source) to \(target)"
        case .targetRegionNotReady(let region):
            return "Target region \(region) is not ready for migration"
        case .adaptationFailed(let reason):
            return "Profile adaptation failed: \(reason)"
        }
    }
}