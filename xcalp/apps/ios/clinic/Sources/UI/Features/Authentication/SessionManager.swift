import Combine
import Foundation
import UIKit

/// Manages user session and authentication state
public final class SessionManager {
    public static let shared = SessionManager()
    
    private let keychainManager = KeychainManager.shared
    private let logger = XcalpLogger.shared
    private let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes
    private let backgroundTimeout: TimeInterval = 5 * 60 // 5 minutes
    
    @Published private(set) var currentSession: Session?
    private var sessionTimer: Timer?
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppBackground() {
        logger.info("App entered background")
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: backgroundTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleSessionTimeout()
        }
    }
    
    @objc private func handleAppForeground() {
        logger.info("App entered foreground")
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(
            withTimeInterval: sessionTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleSessionTimeout()
        }
    }
    
    /// Start a new session
    /// - Parameter user: Authenticated user info
    public func startSession(user: UserInfo) throws {
        let session = Session(
            id: UUID().uuidString,
            userId: user.id,
            createdAt: Date()
        )
        
        do {
            try storeSession(session)
            currentSession = session
            logger.info("Created new session for user: \(user.id)")
            
            // Log HIPAA event
            HIPAALogger.shared.log(
                type: .authentication,
                action: "Session Started",
                userID: user.id,
                details: "New session: \(session.id)"
            )
        } catch {
            logger.error("Failed to create session for user: \(user.id)")
            throw SecurityError.authentication("Failed to create session: \(error.localizedDescription)")
        }
    }
    
    /// End current session
    public func endSession() throws {
        guard let session = currentSession else { return }
        
        do {
            try invalidateSession()
            
            // Log HIPAA event
            HIPAALogger.shared.log(
                type: .authentication,
                action: "Session Ended",
                userID: session.userId,
                details: "Session terminated: \(session.id)"
            )
        } catch {
            logger.error("Failed to end session")
            throw SecurityError.authentication("Failed to end session: \(error.localizedDescription)")
        }
    }
    
    /// Validate current session
    /// - Returns: Whether session is valid
    public func validateSession() -> Bool {
        guard let session = currentSession else { return false }
        return Date().timeIntervalSince(session.createdAt) < sessionTimeout
    }
    
    /// Extend current session
    public func extendSession() throws {
        guard var session = currentSession else { return }
        
        session.createdAt = Date()
        currentSession = session
        
        // Update stored session
        do {
            try storeSession(session)
            logger.info("Session extended successfully")
            
            // Log HIPAA event
            HIPAALogger.shared.log(
                type: .authentication,
                action: "Session Extended",
                userID: session.userId,
                details: "Session extended: \(session.id)"
            )
        } catch {
            logger.error("Failed to extend session")
            throw SecurityError.authentication("Failed to extend session: \(error.localizedDescription)")
        }
    }
    
    /// Get current session
    public func getCurrentSession() throws -> Session? {
        if let session = currentSession {
            return session
        }
        
        do {
            let data = try keychainManager.retrieve(forKey: "currentSession")
            let session = try JSONDecoder().decode(Session.self, from: data)
            
            if isSessionValid(session) {
                currentSession = session
                return session
            } else {
                try invalidateSession()
                return nil
            }
        } catch {
            logger.warning("No active session found")
            return nil
        }
    }
    
    /// Invalidate current session
    public func invalidateSession() throws {
        sessionTimer?.invalidate()
        sessionTimer = nil
        currentSession = nil
        
        do {
            try keychainManager.remove(forKey: "currentSession")
            logger.info("Session invalidated successfully")
        } catch {
            logger.error("Failed to invalidate session")
            throw SecurityError.authentication("Failed to invalidate session: \(error.localizedDescription)")
        }
    }
    
    private func storeSession(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        try keychainManager.store(data, forKey: "currentSession")
    }
    
    private func isSessionValid(_ session: Session) -> Bool {
        Date().timeIntervalSince(session.createdAt) < sessionTimeout
    }
    
    private func handleSessionTimeout() {
        logger.warning("Session timed out")
        try? invalidateSession()
    }
}

// MARK: - Supporting Types
extension SessionManager {
    public struct Session: Codable {
        public let id: String
        public let userId: String
        public let createdAt: Date
        
        public init(id: String, userId: String, createdAt: Date) {
            self.id = id
            self.userId = userId
            self.createdAt = createdAt
        }
    }
    
    public struct UserInfo: Codable {
        public let id: String
        public let name: String
        public let role: Role
        public let permissions: [Permission]
        
        public enum Role: String, Codable {
            case admin
            case doctor
            case assistant
        }
        
        public enum Permission: String, Codable {
            case viewPatients
            case editPatients
            case performScans
            case editTreatments
            case exportData
            case manageUsers
        }
    }
}
