import Foundation

actor TemplateRecommendationEngine {
    private let analytics: TemplateAnalytics
    private let templateManager: TemplateManager
    
    init(analytics: TemplateAnalytics, templateManager: TemplateManager) {
        self.analytics = analytics
        self.templateManager = templateManager
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
        let templates = try await templateManager.loadTemplates()
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
            if let treatmentTime = treatmentTime {
                let timeScore = calculateTimeScore(
                    target: treatmentTime,
                    average: stats.averageTreatmentTime
                )
                confidence *= timeScore
                
                if timeScore > 0.8 {
                    reasons.append("Matches time requirements")
                }
            }
            
            // Add success rate context
            if stats.successRate > 0.9 {
                reasons.append("High success rate (\(Int(stats.successRate * 100))%)")
                confidence *= 1.2 // Boost confidence for highly successful templates
            }
            
            // Add usage frequency context
            if stats.useCount > 10 {
                reasons.append("Frequently used (\(stats.useCount) times)")
                confidence *= 1.1 // Boost confidence for well-tested templates
            }
            
            if confidence > 0.5 { // Only include reasonably confident recommendations
                recommendations.append(Recommendation(
                    template: template,
                    confidence: confidence,
                    reason: reasons.joined(separator: ", ")
                ))
            }
        }
        
        // Sort by confidence and return top recommendations
        return recommendations
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(5)
            .map { $0 }
    }
    
    private func calculateBaseConfidence(_ stats: TemplateAnalytics.TemplateUsageStats) -> Double {
        // Base confidence from success rate and usage
        let usageWeight = min(Double(stats.useCount) / 10.0, 1.0) // Max weight at 10 uses
        return (stats.successRate * 0.7 + usageWeight * 0.3)
    }
    
    private func calculateDensityScore(target: Double, range: ClosedRange<Double>) -> Double {
        if range.contains(target) {
            return 1.0
        }
        
        let distance = min(
            abs(target - range.lowerBound),
            abs(target - range.upperBound)
        )
        return max(0, 1 - (distance / 20.0)) // 20 grafts/cm² difference = 0 score
    }
    
    private func calculateRegionScore(target: Int, actual: Int) -> Double {
        let difference = abs(target - actual)
        return max(0, 1 - Double(difference) / 3.0) // 3 region difference = 0 score
    }
    
    private func calculateTimeScore(target: TimeInterval, average: TimeInterval) -> Double {
        let difference = abs(target - average)
        return max(0, 1 - (difference / (30 * 60))) // 30 minutes difference = 0 score
    }
}