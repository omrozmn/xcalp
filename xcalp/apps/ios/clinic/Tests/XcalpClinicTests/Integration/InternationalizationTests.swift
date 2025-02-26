import XCTest
@testable import XcalpClinic

class InternationalizationTests: XCTestCase {
    var dataSync: CrossPlatformSyncManager!
    var rtlManager: RTLSupportManager!
    var languageManager: LanguageManager!
    var complianceManager: RegionalComplianceManager!
    
    override func setUp() {
        super.setUp()
        dataSync = CrossPlatformSyncManager(cloudStorage: MockCloudStorage())
        rtlManager = RTLSupportManager.shared
        languageManager = LanguageManager.shared
        complianceManager = RegionalComplianceManager.shared
    }
    
    // MARK: - Cross Platform Data Tests
    
    func testCrossDeviceDataSync() async throws {
        // Test data synchronization between platforms
        let testData = createTestScanData()
        let syncResult = try await dataSync.sync(data: testData)
        
        XCTAssertTrue(syncResult.success)
        XCTAssertNotNil(syncResult.version)
        XCTAssertTrue(syncResult.conflicts.isEmpty)
    }
    
    func testDataFormatCompatibility() throws {
        // Test data format compatibility across platforms
        let nativeData = createTestScanData()
        let crossPlatformData = try XCScanData.fromNative(nativeData)
        let reconvertedData = try crossPlatformData.toNative()
        
        XCTAssertEqual(nativeData.id, reconvertedData.id)
        XCTAssertEqual(nativeData.points.count, reconvertedData.points.count)
    }
    
    // MARK: - RTL Support Tests
    
    func testRTLLayoutTransformation() {
        // Test RTL layout handling
        let originalFrame = CGRect(x: 10, y: 20, width: 100, height: 50)
        let transformedFrame = rtlManager.transformLayoutForRTL(originalFrame)
        
        // Should be mirrored in RTL mode
        if rtlManager.isRTLEnabled {
            XCTAssertEqual(transformedFrame.minX, UIScreen.main.bounds.width - originalFrame.maxX)
        }
    }
    
    func testRTLTextAlignment() {
        // Test text alignment in RTL mode
        let alignment = rtlManager.textAlignment()
        
        if languageManager.getCurrentLanguage().direction == .rightToLeft {
            XCTAssertEqual(alignment, .trailing)
        } else {
            XCTAssertEqual(alignment, .leading)
        }
    }
    
    // MARK: - Language Support Tests
    
    func testLanguageSwitching() async throws {
        // Test language switching
        try languageManager.setLanguage("ar")
        XCTAssertEqual(languageManager.getCurrentLanguage().code, "ar")
        
        try languageManager.setLanguage("en")
        XCTAssertEqual(languageManager.getCurrentLanguage().code, "en")
    }
    
    func testLocalizationConsistency() {
        // Test localization across supported languages
        for language in languageManager.availableLanguages() {
            try? languageManager.setLanguage(language.code)
            
            // Check critical UI elements
            let testKeys = ["scan.start", "scan.stop", "analysis.begin"]
            for key in testKeys {
                let localizedString = languageManager.localizedString(key)
                XCTAssertFalse(localizedString.contains("??"))
                XCTAssertNotEqual(localizedString, key)
            }
        }
    }
    
    // MARK: - Compliance Tests
    
    func testRegionalCompliance() async throws {
        let testData = createTestPatientData()
        
        // Test compliance in different regions
        for region in [Region.europeanUnion, .unitedStates, .turkey] {
            try complianceManager.setRegion(region)
            
            // Verify required consents
            let consents = complianceManager.getRequiredConsents()
            XCTAssertFalse(consents.isEmpty)
            
            // Verify data retention periods
            let retentionPeriod = complianceManager.getDataRetentionPeriod()
            XCTAssertGreaterThan(retentionPeriod, 0)
            
            // Test compliance validation
            try complianceManager.validateCompliance(for: testData)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestScanData() -> ScanData {
        // Create test scan data
        return ScanData(
            id: UUID(),
            points: [Point3D(position: .zero, confidence: 1.0, classification: .surface)],
            analysis: nil,
            annotations: []
        )
    }
    
    private func createTestPatientData() -> PatientData {
        // Create test patient data with all required fields
        return PatientData(
            id: UUID(),
            consents: Set(ConsentType.allCases),
            dataRetentionDate: Date().addingTimeInterval(365 * 24 * 3600),
            privacyAccepted: true
        )
    }
}