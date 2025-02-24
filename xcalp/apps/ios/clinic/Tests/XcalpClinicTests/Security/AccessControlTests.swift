import ComposableArchitecture
@testable import XcalpClinic
import XCTest

final class AccessControlTests: XCTestCase {
    func testUserAuthentication() async throws {
        let auth = AuthenticationManager.shared
        
        // Test valid credentials
        let validCredentials = Credentials(
            username: "test-doctor",
            password: "Test@123!",
            role: .doctor
        )
        let token = try await auth.authenticate(credentials: validCredentials)
        XCTAssertNotNil(token)
        
        // Test invalid credentials
        let invalidCredentials = Credentials(
            username: "test-doctor",
            password: "wrong",
            role: .doctor
        )
        await XCTAssertThrowsError(try await auth.authenticate(credentials: invalidCredentials))
        
        // Test token validation
        XCTAssertTrue(try auth.validateToken(token))
        
        // Test token expiration
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        auth.invalidateToken(token)
        XCTAssertFalse(try auth.validateToken(token))
    }
    
    func testRoleBasedAccess() throws {
        let rbac = RBACManager.shared
        
        // Test doctor permissions
        let doctorPermissions = rbac.getPermissions(for: .doctor)
        XCTAssertTrue(doctorPermissions.contains(.performScans))
        XCTAssertTrue(doctorPermissions.contains(.viewPatientData))
        XCTAssertTrue(doctorPermissions.contains(.editTreatmentPlan))
        
        // Test nurse permissions
        let nursePermissions = rbac.getPermissions(for: .nurse)
        XCTAssertTrue(nursePermissions.contains(.viewPatientData))
        XCTAssertFalse(nursePermissions.contains(.editTreatmentPlan))
        
        // Test patient permissions
        let patientPermissions = rbac.getPermissions(for: .patient)
        XCTAssertTrue(patientPermissions.contains(.viewOwnData))
        XCTAssertFalse(patientPermissions.contains(.viewPatientData))
    }
    
    func testAccessAuditing() async throws {
        let auditor = AccessAuditor.shared
        
        // Test access logging
        let accessEvent = AccessEvent(
            userID: "test-doctor",
            role: .doctor,
            resource: "patient-123",
            action: .view,
            timestamp: Date()
        )
        try auditor.logAccess(accessEvent)
        
        // Test access verification
        let logs = try await auditor.getAccessLogs(for: "patient-123")
        XCTAssertTrue(logs.contains { $0.userID == "test-doctor" })
        
        // Test unauthorized access detection
        let unauthorizedEvent = AccessEvent(
            userID: "test-nurse",
            role: .nurse,
            resource: "treatment-plan-123",
            action: .edit,
            timestamp: Date()
        )
        XCTAssertFalse(try auditor.isAuthorized(unauthorizedEvent))
    }
    
    func testSessionManagement() async throws {
        let sessionManager = SessionManager.shared
        
        // Test session creation
        let session = try await sessionManager.createSession(
            userID: "test-doctor",
            role: .doctor
        )
        XCTAssertNotNil(session)
        
        // Test session validation
        XCTAssertTrue(try sessionManager.validateSession(session))
        
        // Test session timeout
        try await Task.sleep(nanoseconds: UInt64(sessionManager.sessionTimeout * 1_000_000_000))
        XCTAssertFalse(try sessionManager.validateSession(session))
        
        // Test concurrent sessions
        let maxSessions = sessionManager.maxConcurrentSessions
        var sessions: [String] = []
        
        for _ in 0..<maxSessions {
            let newSession = try await sessionManager.createSession(
                userID: "test-doctor",
                role: .doctor
            )
            sessions.append(newSession)
        }
        
        // Attempt to create one more session
        await XCTAssertThrowsError(
            try await sessionManager.createSession(
                userID: "test-doctor",
                role: .doctor
            )
        )
    }
    
    func testEmergencyAccess() async throws {
        let emergency = EmergencyAccessManager.shared
        
        // Test emergency access grant
        let granted = try await emergency.grantEmergencyAccess(
            userID: "test-doctor",
            reason: "Patient critical condition"
        )
        XCTAssertTrue(granted)
        
        // Test emergency access validation
        XCTAssertTrue(try emergency.validateEmergencyAccess(userID: "test-doctor"))
        
        // Test emergency access logging
        let logs = try emergency.getEmergencyAccessLogs()
        XCTAssertTrue(logs.contains { $0.userID == "test-doctor" })
        
        // Test emergency access revocation
        try await emergency.revokeEmergencyAccess(userID: "test-doctor")
        XCTAssertFalse(try emergency.validateEmergencyAccess(userID: "test-doctor"))
    }
}
