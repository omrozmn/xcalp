import Foundation

actor TemplateAnalytics {
    private var usageStats: [UUID: TemplateUsageStats] = [:]
    private let analyticsStorage = AnalyticsStorage()
    
    struct TemplateUsageStats: Codable {
        var useCount: Int
        var lastUsed: Date
        var successRate: Double
        var averageTreatmentTime: TimeInterval
        var regionCount: Int
        var densityRange: ClosedRange<Double>
        var modifications: Int
    }
    
    func recordTemplateUse(_ template: TreatmentTemplate) async {
        var stats = await getStats(for: template.id)
        stats.useCount += 1
        stats.lastUsed = Date()
        stats.regionCount = template.regions.count
        stats.densityRange = getDensityRange(from: template)
        await updateStats(stats, for: template.id)
    }
    
    func recordTreatmentSuccess(_ templateId: UUID, success: Bool, duration: TimeInterval) async {
        var stats = await getStats(for: templateId)
        let totalTreatments = Double(stats.useCount)
        let currentSuccess = stats.successRate * totalTreatments
        stats.successRate = (currentSuccess + (success ? 1 : 0)) / (totalTreatments + 1)
        stats.averageTreatmentTime = (stats.averageTreatmentTime * totalTreatments + duration) / (totalTreatments + 1)
        await updateStats(stats, for: templateId)
    }
    
    func recordTemplateModification(_ templateId: UUID) async {
        var stats = await getStats(for: templateId)
        stats.modifications += 1
        await updateStats(stats, for: templateId)
    }
    
    func getTemplateInsights(_ templateId: UUID) async -> TemplateUsageStats? {
        return await getStats(for: templateId)
    }
    
    private func getStats(for templateId: UUID) async -> TemplateUsageStats {
        if let stats = usageStats[templateId] {
            return stats
        }
        
        if let savedStats = try? await analyticsStorage.load(TemplateUsageStats.self, forKey: statsKey(for: templateId)) {
            usageStats[templateId] = savedStats
            return savedStats
        }
        
        return TemplateUsageStats(
            useCount: 0,
            lastUsed: Date(),
            successRate: 1.0,
            averageTreatmentTime: 0,
            regionCount: 0,
            densityRange: 0...0,
            modifications: 0
        )
    }
    
    private func updateStats(_ stats: TemplateUsageStats, for templateId: UUID) async {
        usageStats[templateId] = stats
        try? await analyticsStorage.save(stats, forKey: statsKey(for: templateId))
    }
    
    private func statsKey(for templateId: UUID) -> String {
        return "template_stats_\(templateId.uuidString)"
    }
    
    private func getDensityRange(from template: TreatmentTemplate) -> ClosedRange<Double> {
        let densities = template.regions.map { $0.parameters.density }
        guard let min = densities.min(), let max = densities.max() else {
            return 0...0
        }
        return min...max
    }
}

// MARK: - Storage
private actor AnalyticsStorage {
    private let storage = SecureStorage.shared
    
    func save<T: Codable>(_ value: T, forKey key: String) async throws {
        try await storage.save(value, forKey: key)
    }
    
    func load<T: Codable>(_ type: T.Type, forKey key: String) async throws -> T? {
        return try await storage.load(type, forKey: key)
    }
}