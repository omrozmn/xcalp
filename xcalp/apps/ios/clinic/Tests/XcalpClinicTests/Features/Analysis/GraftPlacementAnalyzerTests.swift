import XCTest
@testable import XcalpClinic

final class GraftPlacementAnalyzerTests: XCTestCase {
    var analyzer: GraftPlacementAnalyzer!
    
    override func setUp() async throws {
        try await super.setUp()
        analyzer = try GraftPlacementAnalyzer()
    }
    
    func testOptimalPlacementCalculation() async throws {
        // Create test density map
        let densityMap = DensityMap(
            width: 100,
            height: 100,
            densityValues: Array(repeating: 25.0, count: 10000)  // 25 follicles/cm²
        )
        
        // Calculate optimal placements
        let placements = try await analyzer.calculateOptimalPlacements(
            for: densityMap,
            targetDensity: 45.0,
            minSpacing: 0.15
        )
        
        // Verify placements
        XCTAssertFalse(placements.isEmpty)
        
        // Check each placement
        for placement in placements {
            // Verify graft count
            XCTAssertGreaterThan(placement.graftCount, 0)
            
            // Verify coverage
            XCTAssertGreaterThan(placement.coverage, 0)
            XCTAssertLessThanOrEqual(placement.coverage, 1.0)
            
            // Verify region
            XCTAssertGreaterThan(placement.region.radius, 0)
            XCTAssertGreaterThanOrEqual(placement.region.currentDensity, 0)
            
            // Verify directions
            XCTAssertFalse(placement.directions.isEmpty)
            for direction in placement.directions {
                // Verify direction normalization
                let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
                XCTAssertEqual(length, 1.0, accuracy: 0.001)
            }
        }
        
        // Verify placement spacing
        for i in 0..<placements.count {
            for j in (i + 1)..<placements.count {
                let distance = simd_distance(
                    placements[i].region.center,
                    placements[j].region.center
                )
                XCTAssertGreaterThan(distance, 0.15) // Minimum spacing requirement
            }
        }
    }
    
    func testEmptyDensityMap() async throws {
        // Create empty density map
        let emptyMap = DensityMap(
            width: 100,
            height: 100,
            densityValues: Array(repeating: 0.0, count: 10000)
        )
        
        // Calculate placements
        let placements = try await analyzer.calculateOptimalPlacements(
            for: emptyMap,
            targetDensity: 45.0,
            minSpacing: 0.15
        )
        
        // Verify full coverage needed
        XCTAssertTrue(placements.allSatisfy { $0.coverage > 0.99 })
    }
    
    func testHighDensityMap() async throws {
        // Create high density map
        let highDensityMap = DensityMap(
            width: 100,
            height: 100,
            densityValues: Array(repeating: 50.0, count: 10000) // Above target
        )
        
        // Calculate placements
        let placements = try await analyzer.calculateOptimalPlacements(
            for: highDensityMap,
            targetDensity: 45.0,
            minSpacing: 0.15
        )
        
        // Verify no placements needed
        XCTAssertTrue(placements.isEmpty)
    }
    
    func testInvalidParameters() async throws {
        let densityMap = DensityMap(
            width: 100,
            height: 100,
            densityValues: Array(repeating: 25.0, count: 10000)
        )
        
        // Test invalid target density
        await XCTAssertThrowsError(
            try await analyzer.calculateOptimalPlacements(
                for: densityMap,
                targetDensity: -1.0,
                minSpacing: 0.15
            )
        )
        
        // Test invalid spacing
        await XCTAssertThrowsError(
            try await analyzer.calculateOptimalPlacements(
                for: densityMap,
                targetDensity: 45.0,
                minSpacing: -0.1
            )
        )
    }
    
    func testPerformance() async throws {
        // Create large density map
        let largeDensityMap = DensityMap(
            width: 1000,
            height: 1000,
            densityValues: Array(repeating: 25.0, count: 1_000_000)
        )
        
        measure {
            // Measure performance of placement calculation
            Task {
                _ = try? await analyzer.calculateOptimalPlacements(
                    for: largeDensityMap,
                    targetDensity: 45.0,
                    minSpacing: 0.15
                )
            }
        }
    }
}