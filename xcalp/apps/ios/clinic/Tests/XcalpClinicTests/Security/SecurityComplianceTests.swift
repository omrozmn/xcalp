import ComposableArchitecture
@testable import XcalpClinic
import XCTest

final class SecurityComplianceTests: XCTestCase {
    func testMedicalDataHandling() async throws {
        // Test data
        let testData = "Test Patient Data".data(using: .utf8)!
        let handler = HIPAAMedicalDataHandler.shared
        
        // Test sensitivity validation
        let sensitivity = try handler.validateSensitivity(of: testData)
        XCTAssertEqual(sensitivity, .sensitive)
        
        // Test protection
        let protected = try handler.applyProtection(to: testData, level: sensitivity)
        XCTAssertNotEqual(protected, testData)
        
        // Test export
        let exported = try await handler.handleExport(of: testData, for: .patientRequest)
        XCTAssertNoThrow(try JSONDecoder().decode(HIPAAMedicalDataHandler.ExportPackage.self, from: exported))
    }
    
    func testSessionManagement() async {
        let manager = SessionManager.shared
        
        // Test session start
        let user = SessionManager.UserInfo(
            id: "test-user",
            name: "Test User",
            role: .doctor,
            permissions: [.viewPatients, .performScans]
        )
        
        manager.startSession(user: user)
        XCTAssertTrue(manager.validateSession())
        
        // Test session timeout
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        manager.endSession()
        XCTAssertFalse(manager.validateSession())
    }
    
    func testAuditLogging() throws {
        let logger = HIPAALogger.shared
        
        // Log test event
        logger.log(
            type: .dataAccess,
            action: "Test Access",
            userID: "test-user",
            details: "Testing audit logging"
        )
        
        // Export and verify logs
        let logs = try logger.exportLogs()
        XCTAssertFalse(logs.isEmpty)
    }
    
    func testScanningHIPAACompliance() async throws {
        let store = TestStore(
            initialState: ScanningFeature.State(),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.captureScan = {
                let data = Data([0x00, 0x01, 0x02, 0x03])
                
                // Verify data is protected
                let handler = HIPAAMedicalDataHandler.shared
                let sensitivity = try handler.validateSensitivity(of: data)
                let protected = try handler.applyProtection(to: data, level: sensitivity)
                
                return protected
            }
            $0.scanningClient.checkDeviceCapabilities = { true }
        }
        
        await store.send(.startScanning) {
            $0.isScanning = true
        }
        
        await store.send(.captureButtonTapped)
        
        // Verify scan capture triggers HIPAA logging
        let logs = try HIPAALogger.shared.exportLogs()
        XCTAssertTrue(logs.contains { event in
            event.type == .dataAccess && 
            event.action.contains("Scan")
        })
    }
}
