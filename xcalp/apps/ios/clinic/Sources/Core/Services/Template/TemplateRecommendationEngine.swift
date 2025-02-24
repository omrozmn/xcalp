import Foundation
import Core

enum RecommendationError: Error, CustomStringConvertible {
    case templateLoadingFailed(Error)
    case invalidInput(String)
    
    var description: String {
        switch self {
        case .templateLoadingFailed(let error):
            return "Failed to load templates: \(error.localizedDescription)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}

actor TemplateRecommendationEngine {
    private let analytics: AnalyticsService
    private let templateManager: TemplateService
    private let minConfidenceThreshold: Double
    private let maxRecommendations: Int
    
    init(
        analytics: TemplateAnalytics,
        templateManager: TemplateManager,
        minConfidenceThreshold: Double = 0.5,
        maxRecommendations: Int = 5
    ) {
        self.analytics = analytics
        self.templateManager = templateManager
        self.minConfidenceThreshold = minConfidenceThreshold
        self.maxRecommendations = maxRecommendations
    }
    
    struct Recommendation {
        let template: TreatmentTemplate
        let confidence: Double
        let reason: String
    }
    
    func getRecommendations(
        targetDensity: Double? = nil,
        regionCount: Int? = nil,
        treatmentTime: TimeInterval? = nil
    ) async throws -> [Recommendation] {
        let templates: [TreatmentTemplate]
        do {
            templates = try await templateManager.loadTemplates()
        } catch {
            throw RecommendationError.templateLoadingFailed(error)
        }
        var recommendations: [Recommendation] = []
        
        for template in templates {
            let stats = await analytics.getTemplateInsights(template.id)
            guard let stats = stats else { continue }
            
            var confidence = calculateBaseConfidence(stats)
            var reasons: [String] = []
            
            // Density match
            if let targetDensity = targetDensity {
                let densityScore = calculateDensityScore(
                    target: targetDensity,
                    range: stats.densityRange
                )
                confidence *= densityScore
                
                if densityScore > 0.8 {
                    reasons.append("Optimal density range")
                }
            }
            
            // Region count match
            if let regionCount = regionCount {
                let regionScore = calculateRegionScore(
                    target: regionCount,
                    actual: stats.regionCount
                )
                confidence *= regionScore
                
                if regionScore > 0.8 {
                    reasons.append("Suitable region complexity")
                }
            }
            
            // Treatment time match
