import ComposableArchitecture
@testable import XcalpClinic
import XCTest

final class AuthenticationUITests: XCTestCase {
    import XCTest
    var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        super.setUp()
        app = XCUIApplication()
        app.launchArguments = ["UITesting"]
        app.launch()
    }
    
    func testLoginSuccess() throws {
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        XCTAssertTrue(emailField.exists)
        XCTAssertTrue(passwordField.exists)
        XCTAssertTrue(loginButton.exists)
        
        emailField.tap()
        emailField.typeText("test@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        let dashboardTitle = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
    }
    
    func testLoginWithMFA() throws {
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("mfa@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        let mfaCodeField = app.textFields["Verification Code"]
        XCTAssertTrue(mfaCodeField.waitForExistence(timeout: 5))
        
        mfaCodeField.tap()
        mfaCodeField.typeText("123456")
        
        let verifyButton = app.buttons["Verify"]
        verifyButton.tap()
        
        let dashboardTitle = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
    }
    
    func testMFASetup() throws {
        // First login
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("new@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        // Navigate to MFA setup
        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        
        let setupMFAButton = app.buttons["Set Up Two-Factor Authentication"]
        XCTAssertTrue(setupMFAButton.waitForExistence(timeout: 5))
        setupMFAButton.tap()
        
        // Verify QR code is displayed
        let qrCodeImage = app.images["MFA QR Code"]
        XCTAssertTrue(qrCodeImage.waitForExistence(timeout: 5))
        
        // Enter verification code
        let mfaCodeField = app.textFields["Verification Code"]
        XCTAssertTrue(mfaCodeField.exists)
        
        mfaCodeField.tap()
        mfaCodeField.typeText("123456")
        
        let verifyButton = app.buttons["Verify"]
        verifyButton.tap()
        
        // Verify success message
        let successMessage = app.staticTexts["Two-Factor Authentication Enabled"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: 5))
    }
    
    func testBiometricLogin() throws {
        let biometricButton = app.buttons["Sign in with Face ID"]
        guard biometricButton.exists else {
            // Skip test if biometric authentication is not available
            return
        }
        
        biometricButton.tap()
        
        // Verify successful login
        let dashboardTitle = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
    }
    
    func testLoginFailure() throws {
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("wrong@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("wrongpassword")
        
        loginButton.tap()
        
        let errorMessage = app.staticTexts["Invalid email or password"]
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 5))
    }
    
    func testMFAFailure() throws {
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("mfa@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        let mfaCodeField = app.textFields["Verification Code"]
        XCTAssertTrue(mfaCodeField.waitForExistence(timeout: 5))
        
        mfaCodeField.tap()
        mfaCodeField.typeText("999999") // Wrong code
        
        let verifyButton = app.buttons["Verify"]
        verifyButton.tap()
        
        let errorMessage = app.staticTexts["Invalid verification code"]
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 5))
    }
    
    func testLogout() throws {
        // First login
        try testLoginSuccess()
        
        // Then logout
        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        
        let logoutButton = app.buttons["Log Out"]
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5))
        logoutButton.tap()
        
        // Verify we're back at login screen
        let loginButton = app.buttons["Sign In"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
    }
}

extension AuthenticationUITests {
    func testMFASetupAndRecoveryCodes() throws {
        // Login first
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("new@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        // Navigate to MFA setup
        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        
        let setupMFAButton = app.buttons["Set Up Two-Factor Authentication"]
        XCTAssertTrue(setupMFAButton.waitForExistence(timeout: 5))
        setupMFAButton.tap()
        
        // Verify QR code and recovery codes are displayed
        let qrCodeImage = app.images["MFA QR Code"]
        XCTAssertTrue(qrCodeImage.waitForExistence(timeout: 5))
        
        let recoveryCodesTitle = app.staticTexts["Recovery Codes"]
        XCTAssertTrue(recoveryCodesTitle.exists)
        
        // Check that we have 10 recovery codes
        let recoveryCodes = app.staticTexts.matching(identifier: "RecoveryCode")
        XCTAssertEqual(recoveryCodes.count, 10)
        
        // Test generate new codes
        let generateButton = app.buttons["Generate New Codes"]
        generateButton.tap()
        
        // Verify confirmation dialog
        let confirmButton = app.buttons["Generate"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
        
        // Enter verification code
        let mfaCodeField = app.textFields["Verification Code"]
        XCTAssertTrue(mfaCodeField.exists)
        
        mfaCodeField.tap()
        mfaCodeField.typeText("123456")
        
        let verifyButton = app.buttons["Verify"]
        verifyButton.tap()
        
        // Verify success message
        let successMessage = app.staticTexts["Two-Factor Authentication Enabled"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: 5))
    }
    
    func testMFARecoveryCodeLogin() throws {
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        let loginButton = app.buttons["Sign In"]
        
        emailField.tap()
        emailField.typeText("mfa@xcalp.com")
        
        passwordField.tap()
        passwordField.typeText("password123")
        
        loginButton.tap()
        
        // Click "Use Recovery Code" instead of entering MFA code
        let useRecoveryButton = app.buttons["Use Recovery Code"]
        XCTAssertTrue(useRecoveryButton.waitForExistence(timeout: 5))
        useRecoveryButton.tap()
        
        // Enter recovery code
        let recoveryCodeField = app.textFields["Recovery Code"]
        XCTAssertTrue(recoveryCodeField.exists)
        
        recoveryCodeField.tap()
        recoveryCodeField.typeText("1234567890")
        
        let verifyButton = app.buttons["Verify"]
        verifyButton.tap()
        
        // Verify successful login
        let dashboardTitle = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboardTitle.waitForExistence(timeout: 5))
        
        // Verify warning about used recovery code
        let warningMessage = app.staticTexts["Recovery code used. 9 codes remaining."]
        XCTAssertTrue(warningMessage.waitForExistence(timeout: 5))
    }
}
