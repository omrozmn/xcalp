import XCTest
import ComposableArchitecture
@testable import XcalpClinic

final class AnalysisFeatureTests: XCTestCase {
    func testDensityAnalysis() async {
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: AnalysisFeature()
        ) {
            $0.analysisClient.analyzeDensity = {
                [
                    AnalysisFeature.AnalysisResult(
                        type: .densityMapping,
                        date: Date(),
                        summary: "Region density: 45 follicles/cm²"
                    )
                ]
            }
            $0.analysisClient.monitorProgress = {
                AsyncStream { continuation in
                    continuation.yield(0.5)
                    continuation.yield(1.0)
                    continuation.finish()
                }
            }
        }
        
        await store.send(.selectAnalysisType(.densityMapping)) {
            $0.selectedAnalysisType = .densityMapping
        }
        
        await store.send(.startAnalysis) {
            $0.isAnalyzing = true
            $0.progress = 0.0
        }
        
        await store.receive(.updateProgress(0.5)) {
            $0.progress = 0.5
        }
        
        await store.receive(.updateProgress(1.0)) {
            $0.progress = 1.0
        }
        
        await store.receive(.analysisCompleted([
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: store.state.results[0].date,
                summary: "Region density: 45 follicles/cm²"
            )
        ])) {
            $0.isAnalyzing = false
            $0.results = [
                AnalysisFeature.AnalysisResult(
                    type: .densityMapping,
                    date: $0.results[0].date,
                    summary: "Region density: 45 follicles/cm²"
                )
            ]
        }
    }
    
    func testGraftPlacementAnalysis() async {
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: AnalysisFeature()
        ) {
            $0.analysisClient.analyzeGraftPlacement = {
                [
                    AnalysisFeature.AnalysisResult(
                        type: .graftPlacement,
                        date: Date(),
                        summary: "Optimal graft count: 2000, Coverage: 85%"
                    )
                ]
            }
            $0.analysisClient.monitorProgress = {
                AsyncStream { continuation in
                    continuation.yield(1.0)
                    continuation.finish()
                }
            }
        }
        
        await store.send(.selectAnalysisType(.graftPlacement)) {
            $0.selectedAnalysisType = .graftPlacement
        }
        
        await store.send(.startAnalysis) {
            $0.isAnalyzing = true
            $0.progress = 0.0
        }
        
        await store.receive(.updateProgress(1.0)) {
            $0.progress = 1.0
        }
        
        await store.receive(.analysisCompleted([
            AnalysisFeature.AnalysisResult(
                type: .graftPlacement,
                date: store.state.results[0].date,
                summary: "Optimal graft count: 2000, Coverage: 85%"
            )
        ])) {
            $0.isAnalyzing = false
            $0.results = [
                AnalysisFeature.AnalysisResult(
                    type: .graftPlacement,
                    date: $0.results[0].date,
                    summary: "Optimal graft count: 2000, Coverage: 85%"
                )
            ]
        }
    }
    
    func testGrowthProjectionAnalysis() async {
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: AnalysisFeature()
        ) {
            $0.analysisClient.analyzeGrowthProjection = {
                [
                    AnalysisFeature.AnalysisResult(
                        type: .growthProjection,
                        date: Date(),
                        summary: "Month 6: Expected density 55 follicles/cm²"
                    )
                ]
            }
            $0.analysisClient.monitorProgress = {
                AsyncStream { continuation in
                    continuation.yield(1.0)
                    continuation.finish()
                }
            }
        }
        
        await store.send(.selectAnalysisType(.growthProjection)) {
            $0.selectedAnalysisType = .growthProjection
        }
        
        await store.send(.startAnalysis) {
            $0.isAnalyzing = true
            $0.progress = 0.0
        }
        
        await store.receive(.updateProgress(1.0)) {
            $0.progress = 1.0
        }
        
        await store.receive(.analysisCompleted([
            AnalysisFeature.AnalysisResult(
                type: .growthProjection,
                date: store.state.results[0].date,
                summary: "Month 6: Expected density 55 follicles/cm²"
            )
        ])) {
            $0.isAnalyzing = false
            $0.results = [
                AnalysisFeature.AnalysisResult(
                    type: .growthProjection,
                    date: $0.results[0].date,
                    summary: "Month 6: Expected density 55 follicles/cm²"
                )
            ]
        }
    }
    
    func testAnalysisError() async {
        struct TestError: Error, Equatable {}
        
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: AnalysisFeature()
        ) {
            $0.analysisClient.analyzeDensity = { throw TestError() }
            $0.analysisClient.monitorProgress = {
                AsyncStream { continuation in
                    continuation.yield(0.5)
                    continuation.finish()
                }
            }
        }
        
        await store.send(.selectAnalysisType(.densityMapping)) {
            $0.selectedAnalysisType = .densityMapping
        }
        
        await store.send(.startAnalysis) {
            $0.isAnalyzing = true
            $0.progress = 0.0
        }
        
        await store.receive(.updateProgress(0.5)) {
            $0.progress = 0.5
        }
        
        await store.receive(.setError("The operation couldn't be completed. (XcalpClinicTests.AnalysisFeatureTests.TestError error 1.)")) {
            $0.isAnalyzing = false
            $0.errorMessage = "The operation couldn't be completed. (XcalpClinicTests.AnalysisFeatureTests.TestError error 1.)"
        }
    }
}