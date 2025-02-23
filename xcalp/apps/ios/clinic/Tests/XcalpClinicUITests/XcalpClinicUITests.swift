import XCTest

final class XcalpClinicUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBasicLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        // Basic launch test - verify app loads
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}