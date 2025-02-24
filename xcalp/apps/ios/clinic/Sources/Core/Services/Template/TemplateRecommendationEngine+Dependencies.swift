import Dependencies
import Foundation

extension TemplateRecommendationEngine: DependencyKey {
    static var liveValue: TemplateRecommendationEngine = {
        let analytics = TemplateAnalytics()
        let templateManager = TemplateManager.liveValue
        return TemplateRecommendationEngine(analytics: analytics, templateManager: templateManager)
    }()
}

extension DependencyValues {
    var templateRecommendationEngine: TemplateRecommendationEngine {
        get { self[TemplateRecommendationEngine.self] }
        set { self[TemplateRecommendationEngine.self] = newValue }
    }
}
