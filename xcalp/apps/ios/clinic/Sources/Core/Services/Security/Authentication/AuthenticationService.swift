import Foundation
import LocalAuthentication
import CryptoKit
import Combine

public final class AuthenticationService {
    public static let shared = AuthenticationService()
    
    @Published private(set) var currentSession: UserSession?
    private let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes
    private let maxConcurrentSessions = 3
    private var activeSessions: [String: UserSession] = [:]
    private let queue = DispatchQueue(label: "com.xcalp.clinic.auth", qos: .userInitiated)
    
    private init() {
        setupSessionMonitoring()
    }
    
    /// Authenticate user with biometrics
    /// - Parameters:
    ///   - userID: User identifier
    ///   - role: User's role
    /// - Returns: UserSession if authentication successful
    public func authenticateWithBiometrics(userID: String, role: UserRole) async throws -> UserSession {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AuthenticationError.biometricUnavailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authentication required for medical data access"
            ) { success, error in
                if let error = error {
                    continuation.resume(throwing: AuthenticationError.authenticationFailed(error))
                } else if success {
                    do {
                        let session = try self.createSession(userID: userID, role: role)
                        continuation.resume(returning: session)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: AuthenticationError.authenticationFailed(nil))
                }
            }
        }
    }
    
    /// Create a new session for authenticated user
    /// - Parameters:
    ///   - userID: User identifier
    ///   - role: User's role
    /// - Returns: Created UserSession
    private func createSession(userID: String, role: UserRole) throws -> UserSession {
        queue.sync {
            // Check concurrent session limit
            let userSessions = activeSessions.values.filter { $0.userID == userID }
            if userSessions.count >= maxConcurrentSessions {
                throw AuthenticationError.tooManySessions
            }
            
            // Create new session
            let session = UserSession(
                id: UUID().uuidString,
                userID: userID,
                role: role,
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(sessionTimeout)
            )
            
            activeSessions[session.id] = session
            currentSession = session
            
            // Log HIPAA event
            HIPAALogger.shared.log(
                type: .authentication,
                action: "session_created",
                userID: userID,
                details: "Session ID: \(session.id)"
            )
            
            return session
        }
    }
    
    /// Validate an existing session
    /// - Parameter sessionID: ID of session to validate
    /// - Returns: Whether session is valid
    public func validateSession(_ sessionID: String) -> Bool {
        queue.sync {
            guard let session = activeSessions[sessionID] else {
                return false
            }
            
            if Date() > session.expiresAt {
                activeSessions[sessionID] = nil
                if currentSession?.id == sessionID {
                    currentSession = nil
                }
                return false
            }
            
            return true
        }
    }
    
    /// Terminate a session
    /// - Parameter sessionID: ID of session to terminate
    public func terminateSession(_ sessionID: String) {
        queue.sync {
            guard let session = activeSessions[sessionID] else { return }
            
            activeSessions[sessionID] = nil
            if currentSession?.id == sessionID {
                currentSession = nil
            }
            
            // Log HIPAA event
            HIPAALogger.shared.log(
                type: .authentication,
                action: "session_terminated",
                userID: session.userID,
                details: "Session ID: \(sessionID)"
            )
        }
    }
    
    private func setupSessionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanExpiredSessions()
        }
    }
    
    private func cleanExpiredSessions() {
        queue.async {
            let now = Date()
            let expiredSessions = self.activeSessions.filter { $0.value.expiresAt < now }
            
            for (sessionID, session) in expiredSessions {
                self.activeSessions[sessionID] = nil
                if self.currentSession?.id == sessionID {
                    self.currentSession = nil
                }
                
                // Log HIPAA event
                HIPAALogger.shared.log(
                    type: .authentication,
                    action: "session_expired",
                    userID: session.userID,
                    details: "Session ID: \(sessionID)"
                )
            }
        }
    }
}

public enum AuthenticationError: LocalizedError {
    case biometricUnavailable
    case authenticationFailed(Error?)
    case tooManySessions
    case sessionExpired
    case invalidSession
    
    public var errorDescription: String? {
        switch self {
        case .biometricUnavailable:
            return "Biometric authentication is not available on this device"
        case .authenticationFailed(let error):
            return error?.localizedDescription ?? "Authentication failed"
        case .tooManySessions:
            return "Maximum number of concurrent sessions reached"
        case .sessionExpired:
            return "Session has expired"
        case .invalidSession:
            return "Invalid session"
        }
    }
}

public struct UserSession: Codable, Equatable {
    public let id: String
    public let userID: String
    public let role: UserRole
    public let createdAt: Date
    public let expiresAt: Date
}

public enum UserRole: String, Codable {
    case admin
    case doctor
    case nurse
    case patient
}