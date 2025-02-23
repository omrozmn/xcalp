import XCTest

final class ScanningViewUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        
        // Navigate to scanning view
        app.tabBars.buttons["Scanning"].tap()
    }
    
    func testScanningViewInitialState() throws {
        // Verify initial UI elements are present
        XCTAssertTrue(app.buttons["Start"].exists)
        XCTAssertTrue(app.switches["Voice Guidance"].exists)
        XCTAssertFalse(app.buttons["Capture"].isEnabled)
    }
    
    func testStartStopScanning() throws {
        // Start scanning
        app.buttons["Start"].tap()
        
        // Verify UI updates
        XCTAssertTrue(app.buttons["Stop"].exists)
        XCTAssertTrue(app.buttons["Capture"].isEnabled)
        
        // Stop scanning
        app.buttons["Stop"].tap()
        
        // Verify UI returns to initial state
        XCTAssertTrue(app.buttons["Start"].exists)
        XCTAssertFalse(app.buttons["Capture"].isEnabled)
    }
    
    func testVoiceGuidanceToggle() throws {
        let voiceGuidanceSwitch = app.switches["Voice Guidance"]
        
        // Toggle voice guidance off
        voiceGuidanceSwitch.tap()
        XCTAssertFalse(voiceGuidanceSwitch.isSelected)
        
        // Toggle voice guidance on
        voiceGuidanceSwitch.tap()
        XCTAssertTrue(voiceGuidanceSwitch.isSelected)
    }
    
    func testQualityIndicatorUpdates() throws {
        // Start scanning
        app.buttons["Start"].tap()
        
        // Wait for quality indicator to appear
        let qualityIndicator = app.staticTexts["Good Quality"]
        XCTAssertTrue(qualityIndicator.waitForExistence(timeout: 5))
    }
    
    func testGuideOverlayAppears() throws {
        // Start scanning
        app.buttons["Start"].tap()
        
        // Wait for guide overlay to appear
        let guideOverlay = app.staticTexts["Move closer to the subject"]
        XCTAssertTrue(guideOverlay.waitForExistence(timeout: 5))
    }
    
    func testCaptureScan() throws {
        // Start scanning
        app.buttons["Start"].tap()
        
        // Wait for good quality
        let qualityIndicator = app.staticTexts["Good Quality"]
        XCTAssertTrue(qualityIndicator.waitForExistence(timeout: 5))
        
        // Capture scan
        app.buttons["Capture"].tap()
        
        // Verify scan complete message
        let scanComplete = app.staticTexts["Scan complete!"]
        XCTAssertTrue(scanComplete.waitForExistence(timeout: 5))
    }
}
