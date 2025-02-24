@testable import XcalpClinic
import XCTest

final class SessionManagerTests: XCTestCase {
    var sessionManager: SessionManager!
    var deviceManager: DeviceManager!
    
    let testUserID = "test@xcalp.com"
    var testDeviceID: String!
    
    override func setUp() async throws {
        super.setUp()
        sessionManager = SessionManager.shared
        deviceManager = DeviceManager.shared
        
        // Register a test device
        let device = try await deviceManager.registerDevice(withMFAStatus: true)
        testDeviceID = device.id
    }
    
    func testSessionCreation() async throws {
        let session = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        XCTAssertEqual(session.userID, testUserID)
        XCTAssertEqual(session.deviceID, testDeviceID)
        XCTAssertTrue(session.mfaVerified)
        XCTAssertFalse(session.isExpired)
    }
    
    func testSessionValidation() async throws {
        // Create initial session
        let session = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        // Validate session
        let validatedSession = try await sessionManager.validateSession(session.id)
        XCTAssertGreaterThan(validatedSession.lastActivityAt, session.lastActivityAt)
    }
    
    func testSessionRefresh() async throws {
        // Create initial session
        let session = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        // Refresh session
        let newSession = try await sessionManager.refreshSession(session.id)
        
        // Verify new session
        XCTAssertNotEqual(newSession.id, session.id)
        XCTAssertNotEqual(newSession.accessToken, session.accessToken)
        XCTAssertNotEqual(newSession.refreshToken, session.refreshToken)
        XCTAssertEqual(newSession.userID, session.userID)
        XCTAssertEqual(newSession.deviceID, session.deviceID)
        
        // Verify old session is invalidated
        do {
            _ = try await sessionManager.validateSession(session.id)
            XCTFail("Old session should be invalidated")
        } catch {
            XCTAssertEqual(error as? SessionError, .sessionNotFound)
        }
    }
    
    func testSessionWithUntrustedDevice() async throws {
        // Block the device
        try await deviceManager.blockDevice(testDeviceID)
        
        // Attempt to create session
        do {
            _ = try await sessionManager.createSession(
                userID: testUserID,
                deviceID: testDeviceID,
                mfaVerified: true
            )
            XCTFail("Should fail with untrusted device")
        } catch {
            XCTAssertEqual(error as? DeviceError, .trustLevelTooLow)
        }
    }
    
    func testSessionInvalidation() async throws {
        // Create session
        let session = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        // Invalidate session
        try await sessionManager.invalidateSession(session.id)
        
        // Verify session is invalidated
        do {
            _ = try await sessionManager.validateSession(session.id)
            XCTFail("Session should be invalidated")
        } catch {
            XCTAssertEqual(error as? SessionError, .sessionNotFound)
        }
    }
    
    func testInvalidateAllUserSessions() async throws {
        // Create multiple sessions
        let session1 = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        let session2 = try await sessionManager.createSession(
            userID: testUserID,
            deviceID: testDeviceID,
            mfaVerified: true
        )
        
        // Invalidate all sessions
        try await sessionManager.invalidateAllSessions(for: testUserID)
        
        // Verify all sessions are invalidated
        do {
            _ = try await sessionManager.validateSession(session1.id)
            XCTFail("Session 1 should be invalidated")
        } catch {
            XCTAssertEqual(error as? SessionError, .sessionNotFound)
        }
        
        do {
            _ = try await sessionManager.validateSession(session2.id)
            XCTFail("Session 2 should be invalidated")
        } catch {
            XCTAssertEqual(error as? SessionError, .sessionNotFound)
        }
    }
}
