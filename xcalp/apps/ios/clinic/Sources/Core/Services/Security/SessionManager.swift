import CryptoKit
import Foundation
import KeychainAccess

public struct Session: Codable, Equatable {
    public let id: String
    public let userID: String
    public let deviceID: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public var lastActivityAt: Date
    public let mfaVerified: Bool
    
    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

public enum SessionError: LocalizedError {
    case sessionExpired
    case refreshTokenExpired
    case invalidSession
    case sessionNotFound
    case mfaRequired
    case deviceNotTrusted
    
    public var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session has expired"
        case .refreshTokenExpired: return "Refresh token has expired"
        case .invalidSession: return "Invalid session"
        case .sessionNotFound: return "Session not found"
        case .mfaRequired: return "MFA verification required"
        case .deviceNotTrusted: return "Device not trusted"
        }
    }
}

public final class SessionManager {
    public static let shared = SessionManager()
    
    private let keychain = KeychainManager.shared
    private let logger = XcalpLogger.shared
    private let deviceManager = DeviceManager.shared
    private let mfaManager = MFAManager.shared
    
    private let sessionKeyPrefix = "session:"
    private let sessionDuration: TimeInterval = 3600 // 1 hour
    private let refreshTokenDuration: TimeInterval = 30 * 24 * 3600 // 30 days
    private let activityTimeout: TimeInterval = 15 * 60 // 15 minutes
    
    private init() {}
    
    public func createSession(userID: String, deviceID: String, mfaVerified: Bool = false) async throws -> Session {
        // Verify device trust level
        try await deviceManager.validateDevice(deviceID, requiredTrustLevel: .provisional)
        
        // Check if MFA is required but not verified
        if let mfaConfig = try? await mfaManager.getMFAConfig(for: userID),
           mfaConfig.enabled && !mfaVerified {
            throw SessionError.mfaRequired
        }
        
        let session = Session(
            id: UUID().uuidString,
            userID: userID,
            deviceID: deviceID,
            accessToken: generateToken(),
            refreshToken: generateToken(),
            expiresAt: Date().addingTimeInterval(sessionDuration),
            lastActivityAt: Date(),
            mfaVerified: mfaVerified
        )
        
        try await storeSession(session)
        logger.info("Session created for user: \(userID) on device: \(deviceID)")
        logAuditEvent(action: "Session Created", userID: userID, sessionID: session.id, deviceID: deviceID)
        
        return session
    }
    
    public func validateSession(_ sessionID: String) async throws -> Session {
        guard let session = try await getSession(sessionID) else {
            throw SessionError.sessionNotFound
        }
        
        if session.isExpired {
            throw SessionError.sessionExpired
        }
        
        // Update last activity
        var updatedSession = session
        updatedSession.lastActivityAt = Date()
        try await storeSession(updatedSession)
        logAuditEvent(action: "Session Validated", userID: updatedSession.userID, sessionID: updatedSession.id, deviceID: updatedSession.deviceID)
        
        return updatedSession
    }
    
    public func refreshSession(_ sessionID: String) async throws -> Session {
        guard let session = try await getSession(sessionID) else {
            throw SessionError.sessionNotFound
        }
        
        // Verify device is still trusted
        try await deviceManager.validateDevice(session.deviceID, requiredTrustLevel: .provisional)
        
        // Check if refresh token is still valid (30 days)
        let refreshExpiration = session.expiresAt.addingTimeInterval(refreshTokenDuration)
        guard Date() < refreshExpiration else {
            throw SessionError.refreshTokenExpired
        }
        
        // Create new session
        let newSession = Session(
            id: UUID().uuidString,
            userID: session.userID,
            deviceID: session.deviceID,
            accessToken: generateToken(),
            refreshToken: generateToken(),
            expiresAt: Date().addingTimeInterval(sessionDuration),
            lastActivityAt: Date(),
            mfaVerified: session.mfaVerified
        )
        
        // Store new session and remove old one
        try await storeSession(newSession)
        try await removeSession(sessionID)
        
        logger.info("Session refreshed for user: \(session.userID)")
        logAuditEvent(action: "Session Refreshed", userID: newSession.userID, sessionID: newSession.id, deviceID: newSession.deviceID)
        logger.info("Session refreshed for user: \(session.userID)")
        logAuditEvent(action: "Session Refreshed", userID: newSession.userID, sessionID: newSession.id, deviceID: newSession.deviceID)
        return newSession
    }
    
    public func invalidateSession(_ sessionID: String) async throws {
        guard try await getSession(sessionID) != nil else {
            throw SessionError.sessionNotFound
        }
        
        try await removeSession(sessionID)
        logAuditEvent(action: "Session Invalidated", userID: "", sessionID: sessionID, deviceID: "")
    }
    
    public func invalidateAllSessions(for userID: String) async throws {
        let sessions = try await getAllSessions()
        for session in sessions where session.userID == userID {
            try await removeSession(session.id)
        }
        
        logger.info("All sessions invalidated for user: \(userID)")
    }
    
    private func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
    
    private func storeSession(_ session: Session) async throws {
        let data = try JSONEncoder().encode(session)
        if let sealedBox = try AES.GCM.seal(data, using: SymmetricKey(size: .init(bitCount: 256))).combined {
            try await keychain.store(sealedBox, forKey: "\(sessionKeyPrefix)\(session.id)")
        } else {
            logger.error("Failed to encrypt session data for session: \(session.id)")
            throw SessionError.invalidSession // Or a more appropriate error
        }
    }
    
    private func getSession(_ sessionID: String) async throws -> Session? {
        guard let data = try await keychain.retrieve(forKey: "\(sessionKeyPrefix)\(sessionID)") else {
            return nil
        }
        return try JSONDecoder().decode(Session.self, from: data)
    }
    
    private func removeSession(_ sessionID: String) async throws {
        try await keychain.remove("\(sessionKeyPrefix)\(sessionID)")
    }
    
    private func getAllSessions() async throws -> [Session] {
        let keys = try await keychain.allKeys().filter { $0.hasPrefix(sessionKeyPrefix) }
        var sessions: [Session] = []
        
        for key in keys {
            if let data = try await keychain.retrieve(forKey: key),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                sessions.append(session)
            }
        }
        
        return sessions
    }
    
    private func logAuditEvent(action: String, userID: String, sessionID: String, deviceID: String) {
        logger.info("Audit: \(action) - User: \(userID), Session: \(sessionID), Device: \(deviceID)")
        // TODO: Implement more robust audit logging (e.g., store logs in a database)
    }
}
