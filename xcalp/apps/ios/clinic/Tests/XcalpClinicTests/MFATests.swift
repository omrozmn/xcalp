import Core
@testable import XcalpClinic
import XCTest

final class MFATests: XCTestCase {
    var mfaManager: MFAManager!
    let testUserID = "test@xcalp.com"
    
    override func setUp() {
        super.setUp()
        mfaManager = MFAManager.shared
    }
    
    func testMFASetup() async throws {
        // Test MFA setup
        let setupResult = try await mfaManager.setupMFA(type: .authenticatorApp, for: testUserID)
        
        // Verify secret and recovery codes
        XCTAssertFalse(setupResult.secret.isEmpty)
        XCTAssertEqual(setupResult.recoveryCodes.count, 10)
        XCTAssertEqual(setupResult.recoveryCodes.first?.count, 10)
        
        // Test invalid verification code
        do {
            try await mfaManager.verifyAndEnableMFA(code: "000000", for: testUserID)
            XCTFail("Should fail with invalid code")
        } catch {
            XCTAssertTrue(error is MFAError)
            XCTAssertEqual(error as? MFAError, .invalidCode)
        }
        
        // Test recovery code generation
        let newCodes = try await mfaManager.generateNewRecoveryCodes(for: testUserID)
        XCTAssertEqual(newCodes.count, 10)
        XCTAssertNotEqual(newCodes, setupResult.recoveryCodes)
    }
    
    func testMFAVerification() async throws {
        // Setup MFA
        let setupResult = try await mfaManager.setupMFA(type: .authenticatorApp, for: testUserID)
        
        // Test rate limiting
        for _ in 0..<5 {
            do {
                try await mfaManager.verifyMFA(code: "000000", for: testUserID)
            } catch {
                // Expected to fail
            }
        }
        
        do {
            try await mfaManager.verifyMFA(code: "000000", for: testUserID)
            XCTFail("Should fail with too many attempts")
        } catch {
            XCTAssertTrue(error is MFAError)
            XCTAssertEqual(error as? MFAError, .tooManyAttempts)
        }
        
        // Test recovery code
        let recoveryCode = setupResult.recoveryCodes[0]
        try await mfaManager.verifyMFA(code: recoveryCode, for: testUserID)
        
        // Verify recovery code was consumed
        do {
            try await mfaManager.verifyMFA(code: recoveryCode, for: testUserID)
            XCTFail("Should fail with used recovery code")
        } catch {
            XCTAssertTrue(error is MFAError)
            XCTAssertEqual(error as? MFAError, .invalidCode)
        }
    }
    
    func testTOTPVerification() async throws {
        // Setup MFA
        let setupResult = try await mfaManager.setupMFA(type: .authenticatorApp, for: testUserID)
        
        // Generate a valid TOTP code using the secret
        let validCode = generateTOTPCode(secret: setupResult.secret)
        
        // Test valid code
        try await mfaManager.verifyAndEnableMFA(code: validCode, for: testUserID)
        
        // Test that MFA is now enabled
        try await mfaManager.verifyMFA(code: validCode, for: testUserID)
    }
    
    private func generateTOTPCode(secret: String) -> String {
        // This is a simplified TOTP implementation for testing
        // In production, use a proper TOTP library
        let currentTime = Int(Date().timeIntervalSince1970 / 30)
        let hash = "\(currentTime)\(secret)".data(using: .utf8)!
        let code = abs(hash.hashValue) % 1000000
        return String(format: "%06d", code)
    }
}
