import Foundation
import LocalAuthentication

public actor SessionManager {
    public static let shared = SessionManager()
    
    private let keychain: KeychainService
    private let analytics: AnalyticsService
    private let hipaaLogger: HIPAALogger
    
    private var currentSession: Session?
    private var sessionTimer: Task<Void, Never>?
    private let sessionTimeout: TimeInterval = 15 * 60 // 15 minutes
    
    private init(
        keychain: KeychainService = .shared,
        analytics: AnalyticsService = .shared,
        hipaaLogger: HIPAALogger = .shared
    ) {
        self.keychain = keychain
        self.analytics = analytics
        self.hipaaLogger = hipaaLogger
    }
    
    public var currentUser: User? {
        get async {
            await validateSession()
            return currentSession?.user
        }
    }
    
    public var isAuthenticated: Bool {
        get async {
            await validateSession()
            return currentSession != nil
        }
    }
    
    public func authenticate(username: String, password: String) async throws -> User {
        // Log authentication attempt
        await hipaaLogger.log(
            event: .authenticationAttempt,
            details: [
                "username": username,
                "timestamp": Date()
            ]
        )
        
        // Verify biometric authentication first
        try await verifyBiometricAuthentication()
        
        // Verify credentials
        guard let storedPassword = try await keychain.loadCredential(
            username: username,
            service: "com.xcalp.clinic.auth"
        ) else {
            throw AuthenticationError.invalidCredentials
        }
        
        guard password == storedPassword else {
            throw AuthenticationError.invalidCredentials
        }
        
        // Create new session
        let user = User(id: UUID().uuidString, username: username)
        let session = Session(user: user, createdAt: Date())
        currentSession = session
        
        // Start session timer
        startSessionTimer()
        
        // Log successful authentication
        await hipaaLogger.log(
            event: .authenticationSuccess,
            details: [
                "userId": user.id,
                "timestamp": Date()
            ]
        )
        
        analytics.track(event: .userLoggedIn)
        
        return user
    }
    
    public func logout() async {
        await hipaaLogger.log(
            event: .userLogout,
            details: [
                "userId": currentSession?.user.id ?? "unknown",
                "timestamp": Date()
            ]
        )
        
        currentSession = nil
        sessionTimer?.cancel()
        sessionTimer = nil
        
        analytics.track(event: .userLoggedOut)
    }
    
    private func validateSession() async {
        guard let session = currentSession else { return }
        
        if Date().timeIntervalSince(session.createdAt) > sessionTimeout {
            await logout()
        }
    }
    
    private func startSessionTimer() {
        sessionTimer?.cancel()
        sessionTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(sessionTimeout) * 1_000_000_000)
            await logout()
        }
    }
    
    private func verifyBiometricAuthentication() async throws {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthenticationError.biometricUnavailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access patient data"
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AuthenticationError.biometricFailed)
                }
            }
        }
    }
}

// MARK: - Types

extension SessionManager {
    struct Session {
        let user: User
        let createdAt: Date
    }
    
    public struct User: Equatable, Identifiable {
        public let id: String
        public let username: String
    }
    
    public enum AuthenticationError: LocalizedError {
        case invalidCredentials
        case sessionExpired
        case biometricUnavailable
        case biometricFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "Invalid username or password"
            case .sessionExpired:
                return "Your session has expired. Please log in again"
            case .biometricUnavailable:
                return "Biometric authentication is not available"
            case .biometricFailed:
                return "Biometric authentication failed"
            }
        }
    }
}

extension HIPAALogger.Event {
    static let authenticationAttempt = HIPAALogger.Event(name: "authentication_attempt", isSecuritySensitive: true)
    static let authenticationSuccess = HIPAALogger.Event(name: "authentication_success", isSecuritySensitive: true)
    static let userLogout = HIPAALogger.Event(name: "user_logout", isSecuritySensitive: true)
}

extension AnalyticsService.Event {
    static let userLoggedIn = AnalyticsService.Event(name: "user_logged_in")
    static let userLoggedOut = AnalyticsService.Event(name: "user_logged_out")
}