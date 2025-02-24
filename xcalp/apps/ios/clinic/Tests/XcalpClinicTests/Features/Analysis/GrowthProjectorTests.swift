@testable import XcalpClinic
import XCTest

final class GrowthProjectorTests: XCTestCase {
    var projector: GrowthProjector!
    
    override func setUp() async throws {
        try await super.setUp()
        projector = try GrowthProjector()
    }
    
    func testGrowthProjectionCalculation() async throws {
        // Test growth projections at different time points
        let timePoints = [3, 6, 12]
        let projections = try await projector.calculateProjections(months: timePoints)
        
        // Verify projections
        XCTAssertEqual(projections.count, timePoints.count)
        
        // Verify each time point's projection
        for (index, projection) in projections.enumerated() {
            XCTAssertEqual(projection.month, timePoints[index])
            XCTAssertGreaterThan(projection.density, 0)
            XCTAssertGreaterThan(projection.thickness, 0)
            XCTAssertGreaterThan(projection.length, 0)
            XCTAssertGreaterThan(projection.coverage, 0)
            XCTAssertLessThanOrEqual(projection.coverage, 1.0)
            
            if index > 0 {
                // Verify growth progression
                let previousProjection = projections[index - 1]
                XCTAssertGreaterThanOrEqual(projection.density, previousProjection.density)
                XCTAssertGreaterThanOrEqual(projection.length, previousProjection.length)
                XCTAssertGreaterThanOrEqual(projection.coverage, previousProjection.coverage)
            }
        }
    }
    
    func testGrowthPhases() async throws {
        // Test early phase (3 months)
        let earlyProjections = try await projector.calculateProjections(months: [3])
        XCTAssertEqual(earlyProjections.count, 1)
        XCTAssertLessThan(earlyProjections[0].density, 30) // Early growth typically < 30 follicles/cm²
        
        // Test mid phase (6 months)
        let midProjections = try await projector.calculateProjections(months: [6])
        XCTAssertEqual(midProjections.count, 1)
        XCTAssertGreaterThan(midProjections[0].density, earlyProjections[0].density)
        
        // Test late phase (12 months)
        let lateProjections = try await projector.calculateProjections(months: [12])
        XCTAssertEqual(lateProjections.count, 1)
        XCTAssertGreaterThan(lateProjections[0].density, midProjections[0].density)
    }
    
    func testEnvironmentalFactors() async throws {
        // Test seasonal variations
        let winterProjection = try await projector.calculateProjections(months: [1])[0]
        let summerProjection = try await projector.calculateProjections(months: [7])[0]
        
        // Verify seasonal impact
        XCTAssertNotEqual(winterProjection.growth, summerProjection.growth)
        
        // Test stress impact
        let stressedProjection = try await projector.calculateProjectionsWithStress(months: [6])[0]
        let normalProjection = try await projector.calculateProjections(months: [6])[0]
        
        XCTAssertLessThan(stressedProjection.growth, normalProjection.growth)
    }
    
    func testInvalidTimePoints() async {
        // Test negative months
        await XCTAssertThrowsError(try await projector.calculateProjections(months: [-1]))
        
        // Test zero months
        await XCTAssertThrowsError(try await projector.calculateProjections(months: [0]))
        
        // Test too far in future
        await XCTAssertThrowsError(try await projector.calculateProjections(months: [25]))
    }
    
    func testMultipleProjections() async throws {
        let timePoints = Array(1...12) // Monthly projections for a year
        let projections = try await projector.calculateProjections(months: timePoints)
        
        // Verify continuous growth pattern
        var previousDensity: Float = 0
        var previousGrowthRate: Float = 0
        
        for projection in projections {
            let currentDensity = projection.density
            XCTAssertGreaterThanOrEqual(currentDensity, previousDensity)
            
            if previousDensity > 0 {
                let currentGrowthRate = (currentDensity - previousDensity) / Float(projection.month)
                
                // Growth rate should gradually decrease
                if previousGrowthRate > 0 {
                    XCTAssertLessThanOrEqual(currentGrowthRate, previousGrowthRate * 1.2) // Allow 20% variance
                }
                
                previousGrowthRate = currentGrowthRate
            }
            
            previousDensity = currentDensity
        }
    }
    
    func testPerformance() async throws {
        measure {
            Task {
                _ = try? await projector.calculateProjections(months: Array(1...24))
            }
        }
    }
}
