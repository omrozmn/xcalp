import Foundation

actor CulturalAnalysisStore {
    static let shared = CulturalAnalysisStore()
    private let storage = SecureStorage.shared
    private let analysisCache = NSCache<NSString, CachedAnalysis>()
    
    private init() {
        setupCache()
    }
    
    private func setupCache() {
        analysisCache.countLimit = 100
        analysisCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    func store(_ analysis: CulturalAnalysisResult, for patientId: UUID) async throws {
        // Store in cache
        let cached = CachedAnalysis(result: analysis, timestamp: Date())
        analysisCache.setObject(cached, forKey: cacheKey(for: patientId))
        
        // Persist to secure storage
        try await storage.store(
            analysis,
            forKey: storageKey(for: patientId),
            expires: .hours(24)
        )
    }
    
    func getAnalysis(for patientId: UUID) async throws -> CulturalAnalysisResult? {
        // Check cache first
        if let cached = analysisCache.object(forKey: cacheKey(for: patientId)),
           cached.isValid {
            return cached.result
        }
        
        // Try secure storage
        return try await storage.retrieve(
            CulturalAnalysisResult.self,
            forKey: storageKey(for: patientId)
        )
    }
    
    func invalidateAnalysis(for patientId: UUID) async {
        analysisCache.removeObject(forKey: cacheKey(for: patientId))
        try? await storage.remove(forKey: storageKey(for: patientId))
    }
    
    private func cacheKey(for patientId: UUID) -> NSString {
        "cultural_analysis_\(patientId.uuidString)" as NSString
    }
    
    private func storageKey(for patientId: UUID) -> String {
        "cultural_analysis_\(patientId.uuidString)"
    }
}

// MARK: - Supporting Types

private final class CachedAnalysis {
    let result: CulturalAnalysisResult
    let timestamp: Date
    
    init(result: CulturalAnalysisResult, timestamp: Date) {
        self.result = result
        self.timestamp = timestamp
    }
    
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 3600 // 1 hour cache validity
    }
}