import Foundation
import ComposableArchitecture

extension AnalysisFeature {
    struct Analytics {
        @Dependency(\.analyticsClient) static var analytics
        
        static func trackAnalysisStarted(_ type: AnalysisType) {
            analytics.trackAnalysisStarted(type)
        }
        
        static func trackAnalysisCompleted(
            _ type: AnalysisType,
            duration: TimeInterval,
            results: [AnalysisResult]
        ) {
            analytics.trackAnalysisCompleted(type, duration, results)
        }
        
        static func trackAnalysisFailed(
            _ type: AnalysisType,
            error: Error
        ) {
            analytics.trackAnalysisFailed(type, error)
        }
        
        static func trackAnalysisProgress(
            _ type: AnalysisType,
            progress: Double
        ) {
            analytics.trackAnalysisProgress(type, progress)
        }
        
        static func trackUserInteraction(
            _ type: AnalysisType,
            action: String
        ) {
            analytics.trackUserInteraction(type, action)
        }
        
        static func trackResourceUsage(_ type: AnalysisType) {
            analytics.trackResourceUsage(type)
        }
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .selectAnalysisType(type):
                if let type = type {
                    Analytics.trackUserInteraction(type, action: "select_type")
                }
                state.selectedAnalysisType = type
                return .none
                
            case .startAnalysis:
                guard let type = state.selectedAnalysisType else { return .none }
                
                Analytics.trackAnalysisStarted(type)
                state.isAnalyzing = true
                state.progress = 0.0
                state.errorMessage = nil
                
                return .run { [type] send in
                    let startTime = Date()
                    let progressUpdates = await analysisClient.monitorProgress()
                    
                    for await progress in progressUpdates {
                        Analytics.trackAnalysisProgress(type, progress: progress)
                        await send(.updateProgress(progress))
                    }
                    
                    do {
                        let results = try await performAnalysis(type: type)
                        Analytics.trackAnalysisCompleted(
                            type,
                            duration: Date().timeIntervalSince(startTime),
                            results: results
                        )
                        await send(.analysisCompleted(results))
                    } catch {
                        Analytics.trackAnalysisFailed(type, error: error)
                        await send(.setError(error.localizedDescription))
                    }
                    
                    Analytics.trackResourceUsage(type)
                }
                
            // ...existing cases...
            }
        }
    }
}