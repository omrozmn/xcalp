import CryptoKit
import Foundation
import LocalAuthentication

/// HIPAA Compliance Manager that ensures data protection and access control
public final class HIPAACompliance {
    public static let shared = HIPAACompliance()
    
    private init() {
        setupSecurityMonitoring()
    }
    
    /// Ensures data is encrypted before storage
    /// - Parameter data: Data to be encrypted
    /// - Returns: Encrypted data
    public func encryptData(_ data: Data) throws -> Data {
        guard let session = AuthenticationService.shared.currentSession else {
            throw SecurityError.authenticationRequired
        }
        
        guard AccessControlService.shared.validateAccess(for: .editPatientData) else {
            throw SecurityError.unauthorizedAccess
        }
        
        let key = try EncryptionService.shared.retrieveKey(identifier: "patient-data")
        return try EncryptionService.shared.encrypt(data, using: key)
    }
    
    /// Decrypts stored data
    /// - Parameter encryptedData: Data to be decrypted
    /// - Returns: Decrypted data
    public func decryptData(_ encryptedData: Data) throws -> Data {
        guard let session = AuthenticationService.shared.currentSession else {
            throw SecurityError.authenticationRequired
        }
        
        guard AccessControlService.shared.validateAccess(for: .viewPatientData) else {
            throw SecurityError.unauthorizedAccess
        }
        
        let key = try EncryptionService.shared.retrieveKey(identifier: "patient-data")
        return try EncryptionService.shared.decrypt(encryptedData, using: key)
    }
    
    /// Validates access permissions
    /// - Parameter accessLevel: Required access level
    /// - Returns: Whether access is granted
    public func validateAccess(_ accessLevel: AccessLevel) async throws -> Bool {
        guard let session = AuthenticationService.shared.currentSession else {
            let context = LAContext()
            var error: NSError?
            
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw SecurityError.biometricUnavailable
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Authentication required for medical data access"
                ) { success, error in
                    if let error = error {
                        continuation.resume(throwing: SecurityError.authenticationFailed(error))
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
        }
        
        let permission: Permission = {
            switch accessLevel {
            case .read:
                return .viewPatientData
            case .write:
                return .editPatientData
            case .admin:
                return .manageUsers
            }
        }()
        
        return AccessControlService.shared.validateAccess(for: permission)
    }
    
    /// Logs security-relevant events for HIPAA compliance
    /// - Parameter event: Security event to log
    public func logSecurityEvent(_ event: SecurityEvent) {
        HIPAALogger.shared.log(
            type: .security,
            action: event.type.rawValue,
            userID: AuthenticationService.shared.currentSession?.userID ?? "system",
            details: """
                Severity: \(event.severity.rawValue)
                Description: \(event.description)
                Details: \(event.details)
                """
        )
    }
    
    private func setupSecurityMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSecurityThreat(_:)),
            name: .securityThreatDetected,
            object: nil
        )
    }
    
    @objc private func handleSecurityThreat(_ notification: Notification) {
        guard let event = notification.userInfo?["event"] as? SecurityEvent else {
            return
        }
        
        // Log the security threat
        logSecurityEvent(event)
        
        // Take appropriate action based on severity
        switch event.severity {
        case .critical:
            // Terminate all sessions and require re-authentication
            if let userID = event.details["userID"] as? String {
                AuthenticationService.shared.terminateSession(userID)
            }
        case .high:
            // Log and notify administrators
            NotificationCenter.default.post(
                name: .adminNotificationRequired,
                object: nil,
                userInfo: ["event": event]
            )
        default:
            // Just log the event
            break
        }
    }
}

public enum AccessLevel {
    case read
    case write
    case admin
}

public enum SecurityEvent {
    case dataAccessed(type: String)
    case dataModified(type: String)
    case authenticationAttempt(success: Bool)
    case securitySettingChanged(setting: String)
}

public enum SecurityError: LocalizedError {
    case authenticationRequired
    case biometricUnavailable
    case authenticationFailed(Error)
    case unauthorizedAccess
    case encryptionFailed
    case decryptionFailed
    
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required to access this resource"
        case .biometricUnavailable:
            return "Biometric authentication is not available"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .unauthorizedAccess:
            return "Unauthorized access attempt"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        }
    }
}

extension Notification.Name {
    static let adminNotificationRequired = Notification.Name("com.xcalp.clinic.adminNotificationRequired")
}
