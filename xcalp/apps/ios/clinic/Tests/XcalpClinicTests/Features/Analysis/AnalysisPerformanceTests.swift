import XCTest
@testable import XcalpClinic

final class AnalysisPerformanceTests: XCTestCase {
    var analyzer: GraftPlacementAnalyzer!
    var projector: GrowthProjector!
    
    override func setUp() async throws {
        try await super.setUp()
        analyzer = try GraftPlacementAnalyzer()
        projector = try GrowthProjector()
    }
    
    func testDensityAnalysisPerformance() async throws {
        // Create large test data
        let largeMap = DensityMap(
            width: 1024,
            height: 1024,
            densityValues: Array(repeating: 25.0, count: 1024 * 1024)
        )
        
        measure {
            let expectation = XCTestExpectation(description: "Density Analysis")
            Task {
                let startTime = CACurrentMediaTime()
                _ = try? await analyzer.calculateOptimalPlacements(
                    for: largeMap,
                    targetDensity: 45.0,
                    minSpacing: 0.15
                )
                let duration = CACurrentMediaTime() - startTime
                
                // Blueprint requirement: 3D processing < 3s
                XCTAssertLessThan(duration, 3.0)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
    
    func testGrowthProjectionPerformance() async throws {
        measure {
            let expectation = XCTestExpectation(description: "Growth Projection")
            Task {
                let startTime = CACurrentMediaTime()
                _ = try? await projector.calculateProjections(months: Array(1...24))
                let duration = CACurrentMediaTime() - startTime
                
                // Blueprint requirement: Reports < 5s
                XCTAssertLessThan(duration, 5.0)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 6.0)
        }
    }
    
    func testAnalysisResponseTime() async throws {
        let analysisFeature = AnalysisFeature()
        let store = TestStore(
            initialState: AnalysisFeature.State(),
            reducer: analysisFeature
        )
        
        measure {
            let expectation = XCTestExpectation(description: "Analysis Response")
            Task {
                let startTime = CACurrentMediaTime()
                
                await store.send(.selectAnalysisType(.densityMapping))
                await store.send(.startAnalysis)
                
                let duration = CACurrentMediaTime() - startTime
                
                // Blueprint requirement: UI interactions < 100ms
                XCTAssertLessThan(duration, 0.1)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testConcurrentAnalysisPerformance() async throws {
        measure {
            let expectation = XCTestExpectation(description: "Concurrent Analysis")
            Task {
                let startTime = CACurrentMediaTime()
                
                // Run multiple analyses concurrently
                async let densityTask = analyzer.calculateOptimalPlacements(
                    for: DensityMap(width: 512, height: 512, densityValues: Array(repeating: 25.0, count: 512 * 512)),
                    targetDensity: 45.0,
                    minSpacing: 0.15
                )
                async let growthTask = projector.calculateProjections(months: [3, 6, 12])
                
                _ = try? await (densityTask, growthTask)
                
                let duration = CACurrentMediaTime() - startTime
                
                // Combined operations should still meet performance requirements
                XCTAssertLessThan(duration, 5.0)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 6.0)
        }
    }
}