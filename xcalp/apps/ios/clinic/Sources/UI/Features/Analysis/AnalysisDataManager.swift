import ComposableArchitecture
import Foundation

public struct AnalysisDataManager {
    private let hipaaHandler = HIPAAMedicalDataHandler.shared
    private let storageManager = SecureStorageManager.shared
    
    public func saveAnalysisResults(_ results: [AnalysisFeature.AnalysisResult], type: AnalysisFeature.AnalysisType) async throws {
        // Convert results to data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let resultsData = try encoder.encode(results)
        
        // Validate sensitivity and apply protection
        let sensitivity = try hipaaHandler.validateSensitivity(of: resultsData)
        let protectedData = try hipaaHandler.applyProtection(to: resultsData, level: sensitivity)
        
        // Store with metadata
        let metadata = AnalysisMetadata(
            type: type,
            timestamp: Date(),
            sensitivity: sensitivity,
            version: AnalysisFeature.currentVersion
        )
        
        try await storageManager.store(
            protectedData,
            key: "analysis_\(type.rawValue)_\(metadata.timestamp.timeIntervalSince1970)",
            metadata: metadata
        )
        
        // Log HIPAA event
        AnalyticsService.shared.logHIPAAEvent(
            action: .dataCreated,
            resourceType: "analysis_results",
            resourceId: metadata.id.uuidString,
            userId: SessionManager.shared.currentUser?.id ?? "unknown"
        )
    }
    
    public func loadAnalysisResults(type: AnalysisFeature.AnalysisType) async throws -> [AnalysisFeature.AnalysisResult] {
        // Find latest analysis results
        let pattern = "analysis_\(type.rawValue)_*"
        let keys = try await storageManager.listKeys(matching: pattern)
        guard let latestKey = keys.sorted().last else {
            return []
        }
        
        // Load protected data and metadata
        let (protectedData, metadata) = try await storageManager.load(key: latestKey)
        
        // Verify integrity
        guard try hipaaHandler.verifyIntegrity(of: protectedData, signature: metadata.signature) else {
            throw AnalysisError.invalidData("Data integrity check failed")
        }
        
        // Decode results
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AnalysisFeature.AnalysisResult].self, from: protectedData)
    }
    
    public func deleteAnalysisResults(type: AnalysisFeature.AnalysisType) async throws {
        let pattern = "analysis_\(type.rawValue)_*"
        let keys = try await storageManager.listKeys(matching: pattern)
        
        for key in keys {
            try await storageManager.delete(key: key)
        }
        
        // Log HIPAA event
        AnalyticsService.shared.logHIPAAEvent(
            action: .dataDeleted,
            resourceType: "analysis_results",
            resourceId: type.rawValue,
            userId: SessionManager.shared.currentUser?.id ?? "unknown"
        )
    }
}

// MARK: - Supporting Types
private struct AnalysisMetadata: Codable {
    let id: UUID
    let type: AnalysisFeature.AnalysisType
    let timestamp: Date
    let sensitivity: SensitivityLevel
    let version: String
    let signature: Data
    
    init(type: AnalysisFeature.AnalysisType, timestamp: Date, sensitivity: SensitivityLevel, version: String) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.sensitivity = sensitivity
        self.version = version
        
        // Calculate signature for integrity verification
        var hasher = SHA256()
        hasher.update(type.rawValue.data(using: .utf8)!)
        hasher.update(timestamp.timeIntervalSince1970.bitPattern.data)
        hasher.update(sensitivity.rawValue.data(using: .utf8)!)
        hasher.update(version.data(using: .utf8)!)
        self.signature = Data(hasher.finalize())
    }
}

extension AnalysisFeature {
    static let currentVersion = "1.0.0"
}
