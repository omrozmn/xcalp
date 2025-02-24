import XCTest

final class ScanningUITests: XCTestCase {
    private var app: XCUIApplication?
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app?.launch()
    }
    
    func testScanningWorkflow() {
        guard let app = app else { return }
        // Navigate to scanning interface
        app.tabBars.buttons["Scan"].tap()
        
        // Verify scanning setup UI elements
        XCTAssertTrue(app.buttons["Start Scan"].exists)
        XCTAssertTrue(app.staticTexts["Scanning Guidelines"].exists)
        
        // Test scan initiation
        app.buttons["Start Scan"].tap()
        
        // Verify camera permission handling
        let cameraAlert = app.alerts.firstMatch
        if cameraAlert.exists {
            cameraAlert.buttons["Allow"].tap()
        }
        
        // Verify scanning UI elements
        XCTAssertTrue(app.staticTexts["Position the device"].exists)
        XCTAssertTrue(app.buttons["Capture"].exists)
        
        // Test quality indicator
        XCTAssertTrue(app.progressIndicators["Quality Score"].exists)
    }
    
    func testScanningModeSwitch() {
        app.tabBars.buttons["Scan"].tap()
        app.buttons["Start Scan"].tap()
        
        // Test mode switching UI
        let modeSwitch = app.buttons["Scanning Mode"]
        XCTAssertTrue(modeSwitch.exists)
        
        modeSwitch.tap()
        XCTAssertTrue(app.sheets["Select Scanning Mode"].exists)
        
        // Verify available modes
        let modeSheet = app.sheets["Select Scanning Mode"]
        XCTAssertTrue(modeSheet.buttons["LiDAR"].exists)
        XCTAssertTrue(modeSheet.buttons["Photogrammetry"].exists)
        XCTAssertTrue(modeSheet.buttons["Hybrid"].exists)
    }
    
    func testScanPreviewAndSave() {
        app.tabBars.buttons["Scan"].tap()
        app.buttons["Start Scan"].tap()
        
        // Simulate scan completion
        app.buttons["Capture"].tap()
        
        // Verify preview screen
        XCTAssertTrue(app.staticTexts["Scan Preview"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Retake"].exists)
        
        // Test save functionality
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Scan saved successfully"].exists)
    }
    
    func testQualityFeedbackUI() {
        guard let app = app else { return }
        app.tabBars.buttons["Scan"].tap()
        app.buttons["Start Scan"].tap()
        
        // Verify quality indicator elements
        XCTAssertTrue(app.progressIndicators["Surface Coverage"].exists)
        XCTAssertTrue(app.progressIndicators["Point Density"].exists)
        XCTAssertTrue(app.staticTexts["Quality Score"].exists)
        
        // Test quality feedback interaction
        let qualityIndicator = app.progressIndicators["Quality Score"]
        XCTAssertTrue(qualityIndicator.exists)
        
        // Verify guidance elements appear when quality is low
        qualityIndicator.tap()
        XCTAssertTrue(app.staticTexts["Quality Improvement Tips"].exists)
    }
    
    func testScanRetryFlow() {
        guard let app = app else { return }
        app.tabBars.buttons["Scan"].tap()
        app.buttons["Start Scan"].tap()
        
        // Complete initial scan
        app.buttons["Capture"].tap()
        
        // Test low quality scenario
        if app.buttons["Retry Recommended"].exists {
            app.buttons["Retry Recommended"].tap()
            XCTAssertTrue(app.staticTexts["Suggested Angles"].exists)
            XCTAssertTrue(app.buttons["Start Retry"].exists)
            
            // Verify retry guidance
            app.buttons["Start Retry"].tap()
            XCTAssertTrue(app.staticTexts["Follow Angle Guide"].exists)
        }
    }
}
