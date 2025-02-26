import XCTest
@testable import XCalp

class CalibrationTests: XCTestCase {
    var calibrationManager: CalibrationManager!
    
    override func setUp() {
        super.setUp()
        calibrationManager = .shared
    }
    
    override func tearDown() {
        calibrationManager = nil
        super.tearDown()
    }
    
    func testAsianHairCalibration() {
        let basePattern = GrowthPattern(
            direction: SIMD3<Float>(0, 1, 0),
            significance: 0.8,
            variance: 0.2
        )
        
        // Test calibration for different regions
        let regions = ["hairline", "crown", "temples", "midScalp"]
        
        for region in regions {
            let calibrated = calibrationManager.calibrateGrowthPattern(
                pattern: basePattern,
                region: region,
                ethnicity: "asian"
            )
            
            // Verify Asian-specific adjustments
            let expectedAngle: Float = region.contains("temple") ? 15.0 : 10.0
            let angleDifference = calculateAngleDifference(
                calibrated.direction,
                basePattern.direction
            )
            
            XCTAssertEqual(
                angleDifference,
                expectedAngle,
                accuracy: 1.0,
                "Incorrect angle adjustment for Asian \(region)"
            )
            
            // Verify texture characteristics
            XCTAssertEqual(
                calibrated.variance,
                basePattern.variance * 0.3,
                accuracy: 0.01,
                "Incorrect variance adjustment for Asian hair"
            )
        }
    }
    
    func testAfricanHairCalibration() {
        let basePattern = GrowthPattern(
            direction: SIMD3<Float>(0, 1, 0),
            significance: 0.8,
            variance: 0.2
        )
        
        let regions = ["hairline", "crown", "temples", "midScalp"]
        
        for region in regions {
            let calibrated = calibrationManager.calibrateGrowthPattern(
                pattern: basePattern,
                region: region,
                ethnicity: "african"
            )
            
            // Verify African-specific adjustments
            let expectedAngle: Float = region.contains("crown") ? 20.0 : 15.0
            let angleDifference = calculateAngleDifference(
                calibrated.direction,
                basePattern.direction
            )
            
            XCTAssertEqual(
                angleDifference,
                expectedAngle,
                accuracy: 1.0,
                "Incorrect angle adjustment for African \(region)"
            )
            
            // Verify texture characteristics
            XCTAssertEqual(
                calibrated.variance,
                basePattern.variance * 0.5,
                accuracy: 0.01,
                "Incorrect variance adjustment for African hair"
            )
        }
    }
    
    func testCaucasianHairCalibration() {
        let basePattern = GrowthPattern(
            direction: SIMD3<Float>(0, 1, 0),
            significance: 0.8,
            variance: 0.2
        )
        
        let regions = ["hairline", "crown", "temples", "midScalp"]
        
        for region in regions {
            let calibrated = calibrationManager.calibrateGrowthPattern(
                pattern: basePattern,
                region: region,
                ethnicity: "caucasian"
            )
            
            // Verify Caucasian-specific adjustments
            let expectedAngle: Float = region.contains("hairline") ? 12.0 : 8.0
            let angleDifference = calculateAngleDifference(
                calibrated.direction,
                basePattern.direction
            )
            
            XCTAssertEqual(
                angleDifference,
                expectedAngle,
                accuracy: 1.0,
                "Incorrect angle adjustment for Caucasian \(region)"
            )
            
            // Verify texture characteristics
            XCTAssertEqual(
                calibrated.variance,
                basePattern.variance * 0.2,
                accuracy: 0.01,
                "Incorrect variance adjustment for Caucasian hair"
            )
        }
    }
    
    func testCustomProfileCalibration() {
        // Create custom ethnicity profile
        let customProfile = EthnicityProfile(
            growthAngles: RegionalAngles(
                hairline: 70,
                crown: 80,
                temples: 65,
                midScalp: 75
            ),
            densityFactors: RegionalDensityFactors(
                hairline: 1.2,
                crown: 1.1,
                temples: 1.3,
                midScalp: 1.2
            ),
            textureCharacteristics: TextureProfile(
                diameter: 0.07,
                curvature: 0.35,
                variability: 0.25
            )
        )
        
        calibrationManager.addCustomProfile(customProfile, for: "custom")
        
        let basePattern = GrowthPattern(
            direction: SIMD3<Float>(0, 1, 0),
            significance: 0.8,
            variance: 0.2
        )
        
        // Test custom profile calibration
        let regions = ["hairline", "crown", "temples", "midScalp"]
        
        for region in regions {
            let calibrated = calibrationManager.calibrateGrowthPattern(
                pattern: basePattern,
                region: region,
                ethnicity: "custom"
            )
            
            // Verify custom adjustments
            let expectedAngle = customProfile.growthAngles.getAngle(for: region)
            let angleDifference = calculateAngleDifference(
                calibrated.direction,
                basePattern.direction
            )
            
            XCTAssertEqual(
                angleDifference,
                expectedAngle,
                accuracy: 1.0,
                "Incorrect angle adjustment for custom profile \(region)"
            )
            
            // Verify custom texture characteristics
            XCTAssertEqual(
                calibrated.variance,
                basePattern.variance * customProfile.textureCharacteristics.variability,
                accuracy: 0.01,
                "Incorrect variance adjustment for custom profile"
            )
        }
    }
    
    func testDensityCalibration() {
        let baseDensity = 100.0 // hairs/cm²
        let regions = ["hairline", "crown", "temples", "midScalp"]
        let ethnicities = ["asian", "african", "caucasian"]
        
        for ethnicity in ethnicities {
            for region in regions {
                let calibratedDensity = calibrationManager.calibrateDensity(
                    density: baseDensity,
                    region: region,
                    ethnicity: ethnicity
                )
                
                // Verify density adjustments
                switch ethnicity {
                case "asian":
                    let expectedFactor = region.contains("temple") ? 1.2 : 1.1
                    XCTAssertEqual(
                        calibratedDensity,
                        baseDensity * expectedFactor,
                        accuracy: 0.1,
                        "Incorrect density adjustment for Asian \(region)"
                    )
                    
                case "african":
                    let expectedFactor = 0.9
                    XCTAssertEqual(
                        calibratedDensity,
                        baseDensity * expectedFactor,
                        accuracy: 0.1,
                        "Incorrect density adjustment for African \(region)"
                    )
                    
                case "caucasian":
                    XCTAssertEqual(
                        calibratedDensity,
                        baseDensity,
                        accuracy: 0.1,
                        "Incorrect density adjustment for Caucasian \(region)"
                    )
                    
                default:
                    break
                }
            }
        }
    }
    
    private func calculateAngleDifference(
        _ v1: SIMD3<Float>,
        _ v2: SIMD3<Float>
    ) -> Float {
        let angle = acos(dot(normalize(v1), normalize(v2)))
        return angle * 180 / .pi
    }
}