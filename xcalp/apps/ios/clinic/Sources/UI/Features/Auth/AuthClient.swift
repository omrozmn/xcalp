import Foundation
import Dependencies
import LocalAuthentication
import KeychainAccess

public struct AuthClient {
    public var login: @Sendable (String, String) async throws -> AuthResponse
    public var verifyMFA: @Sendable (String) async throws -> AuthResponse
    public var logout: @Sendable () async throws -> Void
    public var saveCredentials: @Sendable (String, String) async throws -> Void
    public var getSavedCredentials: @Sendable () async throws -> Credentials
    public var hasSavedCredentials: @Sendable () async throws -> Bool
    public var requestPasswordReset: @Sendable (String) async throws -> String
    public var resetPassword: @Sendable (String, String) async throws -> Bool
    public var setupMFA: @Sendable (MFAType) async throws -> String
    public var verifyAndEnableMFA: @Sendable (String) async throws -> Bool
    
    public static let liveValue = Self.live
    
    static let live = Self(
        login: { username, password in
            let rateLimiter = RateLimitManager.shared
            
            guard rateLimiter.checkRateLimit(for: username) else {
                throw AuthError.tooManyAttempts
            }
            
            // In a real app, this would make an API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            guard !username.isEmpty, !password.isEmpty else {
                throw AuthError.loginFailed(NSError(domain: "com.xcalp.clinic", code: -1))
            }
            
            // Check if MFA is required
            if let mfaConfig = try? await MFAManager.shared.getMFAConfig(for: username),
               mfaConfig.enabled {
                return AuthResponse(
                    token: "",
                    refreshToken: "",
                    expiresIn: 0,
                    requiresMFA: true,
                    mfaPendingID: UUID().uuidString
                )
            }
            
            rateLimiter.resetAttempts(for: username)
            
            return AuthResponse(
                token: UUID().uuidString,
                refreshToken: UUID().uuidString,
                expiresIn: 3600,
                requiresMFA: false,
                mfaPendingID: nil
            )
        },
        verifyMFA: { code in
            // In a real app, this would verify with the server
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            return AuthResponse(
                token: UUID().uuidString,
                refreshToken: UUID().uuidString,
                expiresIn: 3600,
                requiresMFA: false,
                mfaPendingID: nil
            )
        },
        logout: {
            let keychain = Keychain(service: "com.xcalp.clinic")
            try keychain.remove("credentials")
        },
        saveCredentials: { username, password in
            let keychain = Keychain(service: "com.xcalp.clinic")
            let credentials = Credentials(username: username, password: password)
            let data = try JSONEncoder().encode(credentials)
            try keychain.set(data, key: "credentials")
        },
        getSavedCredentials: {
            let keychain = Keychain(service: "com.xcalp.clinic")
            guard let data = try keychain.getData("credentials") else {
                throw AuthError.credentialsNotFound
            }
            return try JSONDecoder().decode(Credentials.self, from: data)
        },
        hasSavedCredentials: {
            let keychain = Keychain(service: "com.xcalp.clinic")
            return try keychain.contains("credentials")
        },
        requestPasswordReset: { email in
            // In a real app, this would send an email
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            return UUID().uuidString // Simulated reset token
        },
        resetPassword: { token, newPassword in
            // In a real app, this would validate token and update password
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            return true
        },
        setupMFA: { type in
            try await MFAManager.shared.setupMFA(type: type, for: UserSession.shared.currentUserId)
        },
        verifyAndEnableMFA: { code in
            try await MFAManager.shared.verifyAndEnableMFA(code: code, for: UserSession.shared.currentUserId)
        }
    )
    
    public static let testValue = Self(
        login: { _, _ in
            AuthResponse(
                token: "test-token",
                refreshToken: "test-refresh-token",
                expiresIn: 3600,
                requiresMFA: false,
                mfaPendingID: nil
            )
        },
        verifyMFA: { _ in
            AuthResponse(
                token: "test-token",
                refreshToken: "test-refresh-token",
                expiresIn: 3600,
                requiresMFA: false,
                mfaPendingID: nil
            )
        },
        logout: {},
        saveCredentials: { _, _ in },
        getSavedCredentials: {
            Credentials(username: "test", password: "test")
        },
        hasSavedCredentials: { true },
        requestPasswordReset: { _ in "test-token" },
        resetPassword: { _, _ in true },
        setupMFA: { _ in "test-mfa-setup" },
        verifyAndEnableMFA: { _ in true }
    )
}

public struct AuthResponse: Equatable {
    public let token: String
    public let refreshToken: String
    public let expiresIn: TimeInterval
    public let requiresMFA: Bool
    public let mfaPendingID: String?
}

public enum AuthError: Error, Equatable {
    case loginFailed(Error)
    case biometricAuthFailed
    case credentialsNotFound
    case networkError
    case tooManyAttempts
    case mfaRequired
    case mfaFailed
    
    public static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

public struct Credentials: Equatable {
    public let username: String
    public let password: String
}

extension DependencyValues {
    public var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

public struct BiometricAuth {
    public var checkBiometricSupport: @Sendable () async -> BiometricType
    public var authenticate: @Sendable () async throws -> Bool
    
    public static let liveValue = Self.live
    
    static let live = Self(
        checkBiometricSupport: {
            let context = LAContext()
            var error: NSError?
            
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                return .none
            }
            
            switch context.biometryType {
            case .faceID:
                return .faceID
            case .touchID:
                return .touchID
            case .none:
                return .none
            @unknown default:
                return .none
            }
        },
        authenticate: {
            let context = LAContext()
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access the app"
            )
            return true
        }
    )
    
    public static let testValue = Self(
        checkBiometricSupport: { .faceID },
        authenticate: { true }
    )
}

extension DependencyValues {
    public var biometricAuth: BiometricAuth {
        get { self[BiometricAuth.self] }
        set { self[BiometricAuth.self] = newValue }
    }
}
