import Foundation
import NaturalLanguage

class FeedbackAnalyzer {
    static let shared = FeedbackAnalyzer()
    
    private let analytics = AnalyticsService.shared
    private let regionManager = RegionalComplianceManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    private var sentimentAnalyzers: [String: NLModel] = [:]
    private var feedbackCache: [Region: [FeedbackEntry]] = [:]
    private let feedbackQueue = DispatchQueue(label: "com.xcalp.clinic.feedback", qos: .userInitiated)
    
    // Cultural sensitivity thresholds per region
    private var sensitivityThresholds: [Region: FeedbackSensitivity] = [
        .unitedStates: .init(
            sentimentThreshold: 0.6,
            culturalWeight: 0.3,
            privacyWeight: 0.4,
            technicalWeight: 0.3
        ),
        .europeanUnion: .init(
            sentimentThreshold: 0.65,
            culturalWeight: 0.3,
            privacyWeight: 0.5,
            technicalWeight: 0.2
        ),
        .southAsia: .init(
            sentimentThreshold: 0.7,
            culturalWeight: 0.5,
            privacyWeight: 0.3,
            technicalWeight: 0.2
        ),
        .mediterranean: .init(
            sentimentThreshold: 0.7,
            culturalWeight: 0.5,
            privacyWeight: 0.3,
            technicalWeight: 0.2
        ),
        .africanDescent: .init(
            sentimentThreshold: 0.7,
            culturalWeight: 0.5,
            privacyWeight: 0.3,
            technicalWeight: 0.2
        )
    ]
    
    private init() {
        loadSentimentModels()
    }
    
    // MARK: - Public Interface
    
    func analyzeFeedback(_ feedback: UserFeedback) async throws -> FeedbackAnalysis {
        performanceMonitor.startMeasuring("feedback_analysis")
        defer { performanceMonitor.stopMeasuring("feedback_analysis") }
        
        let region = regionManager.getCurrentRegion()
        guard let sensitivity = sensitivityThresholds[region] else {
            throw FeedbackError.unsupportedRegion(region)
        }
        
        // Analyze sentiment
        let sentiment = try await analyzeSentiment(feedback.text, language: feedback.language)
        
        // Extract topics
        let topics = extractTopics(from: feedback.text)
        
        // Identify cultural references
        let culturalReferences = identifyCulturalReferences(
            in: feedback.text,
            region: region
        )
        
        // Calculate impact scores
        let impact = calculateImpactScores(
            sentiment: sentiment,
            topics: topics,
            culturalReferences: culturalReferences,
            sensitivity: sensitivity
        )
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            impact: impact,
            topics: topics,
            culturalReferences: culturalReferences,
            region: region
        )
        
        let analysis = FeedbackAnalysis(
            feedbackId: feedback.id,
            sentiment: sentiment,
            topics: topics,
            culturalReferences: culturalReferences,
            impact: impact,
            recommendations: recommendations,
            timestamp: Date()
        )
        
        // Cache analysis
        cacheFeedbackEntry(
            FeedbackEntry(feedback: feedback, analysis: analysis),
            for: region
        )
        
        // Track analysis
        trackFeedbackAnalysis(analysis, region: region)
        
        return analysis
    }
    
    func getFeedbackTrends(for region: Region) -> FeedbackTrends {
        guard let entries = feedbackCache[region] else {
            return FeedbackTrends(
                averageSentiment: 0,
                topTopics: [],
                culturalSensitivity: 0,
                recommendations: []
            )
        }
        
        let recentEntries = entries.suffix(100)
        
        return FeedbackTrends(
            averageSentiment: calculateAverageSentiment(from: recentEntries),
            topTopics: identifyTopTopics(from: recentEntries),
            culturalSensitivity: calculateCulturalSensitivity(from: recentEntries),
            recommendations: generateTrendRecommendations(from: recentEntries)
        )
    }
    
    // MARK: - Private Methods
    
    private func loadSentimentModels() {
        Task {
            do {
                for language in ["en", "tr", "ar", "hi"] {
                    if let model = try? NLModel(mlModel: loadMLModel(for: language)) {
                        sentimentAnalyzers[language] = model
                    }
                }
            }
        }
    }
    
    private func analyzeSentiment(_ text: String, language: String) async throws -> Float {
        guard let analyzer = sentimentAnalyzers[language] else {
            throw FeedbackError.unsupportedLanguage(language)
        }
        
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        guard let sentiment = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        ).0?.rawValue else {
            throw FeedbackError.sentimentAnalysisFailed
        }
        
        return Float(sentiment) ?? 0
    }
    
    private func extractTopics(from text: String) -> Set<FeedbackTopic> {
        // Implementation would use NLP to identify topics
        return []
    }
    
    private func identifyCulturalReferences(
        in text: String,
        region: Region
    ) -> Set<CulturalReference> {
        // Implementation would identify cultural references
        return []
    }
    
    private func calculateImpactScores(
        sentiment: Float,
        topics: Set<FeedbackTopic>,
        culturalReferences: Set<CulturalReference>,
        sensitivity: FeedbackSensitivity
    ) -> FeedbackImpact {
        let culturalImpact = calculateCulturalImpact(
            culturalReferences,
            sentiment: sentiment
        )
        
        let technicalImpact = calculateTechnicalImpact(
            topics,
            sentiment: sentiment
        )
        
        let privacyImpact = calculatePrivacyImpact(
            topics,
            sentiment: sentiment
        )
        
        let weightedScore = (
            culturalImpact * sensitivity.culturalWeight +
            technicalImpact * sensitivity.technicalWeight +
            privacyImpact * sensitivity.privacyWeight
        )
        
        return FeedbackImpact(
            overall: weightedScore,
            cultural: culturalImpact,
            technical: technicalImpact,
            privacy: privacyImpact
        )
    }
    
    private func generateRecommendations(
        impact: FeedbackImpact,
        topics: Set<FeedbackTopic>,
        culturalReferences: Set<CulturalReference>,
        region: Region
    ) -> [FeedbackRecommendation] {
        var recommendations: [FeedbackRecommendation] = []
        
        // Add cultural recommendations
        if impact.cultural > 0.7 {
            recommendations.append(contentsOf: generateCulturalRecommendations(
                culturalReferences,
                region: region
            ))
        }
        
        // Add technical recommendations
        if impact.technical > 0.7 {
            recommendations.append(contentsOf: generateTechnicalRecommendations(
                topics
            ))
        }
        
        // Add privacy recommendations
        if impact.privacy > 0.7 {
            recommendations.append(contentsOf: generatePrivacyRecommendations(
                topics,
                region: region
            ))
        }
        
        return recommendations
    }
    
    private func cacheFeedbackEntry(_ entry: FeedbackEntry, for region: Region) {
        feedbackQueue.async {
            var entries = self.feedbackCache[region] ?? []
            entries.append(entry)
            
            // Keep last 1000 entries per region
            if entries.count > 1000 {
                entries.removeFirst()
            }
            
            self.feedbackCache[region] = entries
        }
    }
    
    private func trackFeedbackAnalysis(_ analysis: FeedbackAnalysis, region: Region) {
        analytics.trackEvent(
            category: .feedback,
            action: "analysis_complete",
            label: region.rawValue,
            value: Int(analysis.sentiment * 100),
            metadata: [
                "cultural_impact": String(analysis.impact.cultural),
                "technical_impact": String(analysis.impact.technical),
                "privacy_impact": String(analysis.impact.privacy),
                "topics": analysis.topics.map { $0.rawValue }.joined(separator: ",")
            ]
        )
    }
}

// MARK: - Supporting Types

struct UserFeedback {
    let id: UUID
    let text: String
    let language: String
    let timestamp: Date
    let metadata: [String: String]
}

struct FeedbackAnalysis {
    let feedbackId: UUID
    let sentiment: Float
    let topics: Set<FeedbackTopic>
    let culturalReferences: Set<CulturalReference>
    let impact: FeedbackImpact
    let recommendations: [FeedbackRecommendation]
    let timestamp: Date
}

struct FeedbackSensitivity {
    let sentimentThreshold: Float
    let culturalWeight: Float
    let privacyWeight: Float
    let technicalWeight: Float
}

struct FeedbackImpact {
    let overall: Float
    let cultural: Float
    let technical: Float
    let privacy: Float
}

struct FeedbackEntry {
    let feedback: UserFeedback
    let analysis: FeedbackAnalysis
}

struct FeedbackTrends {
    let averageSentiment: Float
    let topTopics: [(FeedbackTopic, Int)]
    let culturalSensitivity: Float
    let recommendations: [FeedbackRecommendation]
}

enum FeedbackTopic: String {
    case scanningExperience = "scanning"
    case culturalConsiderations = "cultural"
    case userInterface = "ui"
    case performance = "performance"
    case privacy = "privacy"
    case documentation = "documentation"
}

enum CulturalReference {
    case religious(Religion)
    case traditional(TraditionalStyle)
    case family(String)
    case community(String)
}

struct FeedbackRecommendation {
    let type: RecommendationType
    let priority: Priority
    let description: String
    let actionItems: [String]
    
    enum RecommendationType {
        case cultural
        case technical
        case privacy
    }
    
    enum Priority {
        case high
        case medium
        case low
    }
}

enum FeedbackError: LocalizedError {
    case unsupportedRegion(Region)
    case unsupportedLanguage(String)
    case sentimentAnalysisFailed
    case topicExtractionFailed
    case culturalAnalysisFailed
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Feedback analysis not supported for region: \(region)"
        case .unsupportedLanguage(let language):
            return "Sentiment analysis not supported for language: \(language)"
        case .sentimentAnalysisFailed:
            return "Failed to analyze sentiment"
        case .topicExtractionFailed:
            return "Failed to extract topics"
        case .culturalAnalysisFailed:
            return "Failed to analyze cultural references"
        }
    }
}