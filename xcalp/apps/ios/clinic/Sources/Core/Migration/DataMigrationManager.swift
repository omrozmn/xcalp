import Foundation

actor DataMigrationManager {
    static let shared = DataMigrationManager()
    
    private let storage = SecureStorage.shared
    private let compliance = RegionalComplianceManager.shared
    private let analytics = AnalyticsService.shared
    private let errorHandler = ErrorHandlingCoordinator.shared
    
    private var activeMigrations: [UUID: MigrationTask] = [:]
    private var migrationQueue = DispatchQueue(label: "com.xcalp.clinic.migration", qos: .userInitiated)
    
    private init() {}
    
    func migrateClinicalData(
        _ data: ClinicalCase,
        from sourceRegion: Region,
        to targetRegion: Region
    ) async throws -> ClinicalCase {
        let migrationId = UUID()
        let task = MigrationTask(
            id: migrationId,
            sourceRegion: sourceRegion,
            targetRegion: targetRegion,
            startTime: Date()
        )
        
        activeMigrations[migrationId] = task
        defer { activeMigrations[migrationId] = nil }
        
        analytics.trackEvent(
            category: .migration,
            action: "start",
            label: "\(sourceRegion.rawValue)_to_\(targetRegion.rawValue)",
            value: 0,
            metadata: ["case_id": data.id.uuidString]
        )
        
        // 1. Validate source data compliance
        try await validateSourceCompliance(data, region: sourceRegion)
        
        // 2. Transform data for target region
        var transformedData = try await transformData(data, for: targetRegion)
        
        // 3. Apply cultural adaptations
        transformedData = try await applyCulturalAdaptations(
            transformedData,
            from: sourceRegion,
            to: targetRegion
        )
        
        // 4. Validate target compliance
        try await validateTargetCompliance(transformedData, region: targetRegion)
        
        // 5. Update documentation and audit trail
        transformedData = try await updateDocumentation(transformedData, task: task)
        
        analytics.trackEvent(
            category: .migration,
            action: "complete",
            label: "\(sourceRegion.rawValue)_to_\(targetRegion.rawValue)",
            value: 1,
            metadata: ["case_id": data.id.uuidString]
        )
        
        return transformedData
    }
    
    private func validateSourceCompliance(_ data: ClinicalCase, region: Region) async throws {
        try await withTimeout(seconds: 30) {
            try await compliance.validateCompliance(data.patientData)
        }
    }
    
    private func transformData(_ data: ClinicalCase, for targetRegion: Region) async throws -> ClinicalCase {
        var transformed = data
        
        // Transform measurements if needed
        if let settings = try? await getRegionSettings(for: targetRegion) {
            transformed = try await transformMeasurements(
                data,
                to: settings.measurementSystem
            )
        }
        
        // Transform documentation format
        transformed = try await transformDocumentation(
            transformed,
            for: targetRegion
        )
        
        // Transform consent requirements
        transformed = try await updateConsents(
            transformed,
            for: targetRegion
        )
        
        return transformed
    }
    
    private func applyCulturalAdaptations(
        _ data: ClinicalCase,
        from sourceRegion: Region,
        to targetRegion: Region
    ) async throws -> ClinicalCase {
        var adapted = data
        
        // Adapt cultural preferences
        if let culturalProfile = adapted.culturalProfile {
            adapted.culturalProfile = try await adaptCulturalProfile(
                culturalProfile,
                from: sourceRegion,
                to: targetRegion
            )
        }
        
        // Adapt treatment planning
        if let planning = adapted.planningDocumentation {
            adapted.planningDocumentation = try await adaptPlanningDocumentation(
                planning,
                from: sourceRegion,
                to: targetRegion
            )
        }
        
        // Adapt post-operative instructions
        if let instructions = adapted.postOperativeInstructions {
            adapted.postOperativeInstructions = try await adaptInstructions(
                instructions,
                for: targetRegion
            )
        }
        
        return adapted
    }
    
    private func validateTargetCompliance(_ data: ClinicalCase, region: Region) async throws {
        try await withTimeout(seconds: 30) {
            // Set temporary region context
            try compliance.setRegion(region)
            // Validate compliance
            try await compliance.validateCompliance(data.patientData)
        }
    }
    
    private func updateDocumentation(_ data: ClinicalCase, task: MigrationTask) async throws -> ClinicalCase {
        var updated = data
        
        // Add migration record
        let migrationRecord = MigrationRecord(
            id: task.id,
            timestamp: Date(),
            sourceRegion: task.sourceRegion,
            targetRegion: task.targetRegion,
            adaptations: task.adaptations
        )
        
        // Update audit trail
        var auditTrail = updated.auditTrail ?? []
        auditTrail.append(AuditEvent(
            id: UUID(),
            timestamp: Date(),
            action: .migration,
            userId: task.id,
            userRole: "system",
            resourceId: updated.id,
            resourceType: "ClinicalCase",
            details: "Data migrated from \(task.sourceRegion) to \(task.targetRegion)"
        ))
        
        updated.auditTrail = auditTrail
        updated.migrationHistory.append(migrationRecord)
        
        return updated
    }
    
    private func withTimeout<T>(seconds: Double, operation: () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MigrationError.timeout
            }
            
            let result = try await group.next()
            group.cancelAll()
            return result!
        }
    }
}

// MARK: - Supporting Types

struct MigrationTask {
    let id: UUID
    let sourceRegion: Region
    let targetRegion: Region
    let startTime: Date
    var adaptations: [CulturalAdaptation] = []
}

struct MigrationRecord: Codable {
    let id: UUID
    let timestamp: Date
    let sourceRegion: Region
    let targetRegion: Region
    let adaptations: [CulturalAdaptation]
}

struct CulturalAdaptation: Codable {
    let type: AdaptationType
    let description: String
    let timestamp: Date
    
    enum AdaptationType: String, Codable {
        case measurement
        case documentation
        case consent
        case culturalPreference
        case treatmentPlanning
        case postOperativeInstructions
    }
}

enum MigrationError: LocalizedError {
    case timeout
    case incompatibleRegions(source: Region, target: Region)
    case missingRequiredData(String)
    case adaptationFailed(String)
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Migration operation timed out"
        case .incompatibleRegions(let source, let target):
            return "Cannot migrate data between incompatible regions: \(source) to \(target)"
        case .missingRequiredData(let detail):
            return "Missing required data for migration: \(detail)"
        case .adaptationFailed(let reason):
            return "Cultural adaptation failed: \(reason)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        }
    }
}