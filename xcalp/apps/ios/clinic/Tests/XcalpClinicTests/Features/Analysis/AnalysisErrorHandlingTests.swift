import XCTest
@testable import XcalpClinic

final class AnalysisErrorHandlingTests: XCTestCase {
    func testModelInitializationError() async {
        let analytics = AnalyticsService.shared
        let expectation = XCTestExpectation(description: "Error logged")
        
        analytics.onErrorLogged = { error, severity, context in
            XCTAssertEqual(error as? AnalysisError, .modelInitializationFailed)
            XCTAssertEqual(severity, .critical)
            XCTAssertEqual(context?["feature"] as? String, "analysis")
            expectation.fulfill()
        }
        
        let feature = AnalysisFeature()
        feature.handleError(AnalysisError.modelInitializationFailed)
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testQualityInsufficientRecovery() async {
        let voiceGuidance = VoiceGuidanceManager.shared
        let expectation = XCTestExpectation(description: "Guidance provided")
        
        voiceGuidance.onGuidanceProvided = { guide in
            XCTAssertEqual(guide, .qualityWarning)
            expectation.fulfill()
        }
        
        let feature = AnalysisFeature()
        feature.handleError(AnalysisError.qualityInsufficient("Low resolution"))
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testResourceExhaustedRecovery() {
        let optimizer = PerformanceOptimizer.shared
        var resourcesCleanedUp = false
        
        optimizer.onCleanup = {
            resourcesCleanedUp = true
        }
        
        let feature = AnalysisFeature()
        feature.handleError(AnalysisError.resourceExhausted)
        
        XCTAssertTrue(resourcesCleanedUp)
    }
    
    func testAnalyticsTracking() async {
        let analytics = AnalyticsService.shared
        var trackedEvents: [String] = []
        
        analytics.onActionLogged = { action, category, _ in
            if category == "analysis" {
                trackedEvents.append(action)
            }
        }
        
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: AnalysisFeature()
        )
        
        await store.send(.selectAnalysisType(.densityMapping))
        await store.send(.startAnalysis)
        await store.receive(.updateProgress(0.5))
        await store.receive(.setError("Test error"))
        
        XCTAssertEqual(trackedEvents, [
            "analysis_interaction",
            "analysis_started",
            "analysis_progress",
            "analysis_failed",
            "analysis_resources"
        ])
    }
    
    func testErrorRecoverySuggestions() {
        let errors: [AnalysisError] = [
            .modelInitializationFailed,
            .invalidData("Test"),
            .processingError("Test"),
            .resourceExhausted,
            .modelExecutionFailed("Test"),
            .qualityInsufficient("Test"),
            .outOfBounds("Test")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertNotNil(error.errorDescription)
        }
    }
    
    func testPerformanceLogging() async {
        let analytics = AnalyticsService.shared
        let expectation = XCTestExpectation(description: "Performance logged")
        
        analytics.onPerformanceLogged = { name, duration, memoryUsage in
            XCTAssertTrue(name.starts(with: "analysis_"))
            XCTAssertGreaterThan(duration, 0)
            XCTAssertGreaterThan(memoryUsage, 0)
            expectation.fulfill()
        }
        
        let type = AnalysisFeature.AnalysisType.densityMapping
        AnalysisFeature.Analytics.trackAnalysisCompleted(
            type,
            duration: 1.5,
            results: []
        )
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}