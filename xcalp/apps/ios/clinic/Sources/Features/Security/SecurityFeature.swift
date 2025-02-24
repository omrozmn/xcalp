import CryptoKit
import Foundation
import LocalAuthentication

public struct SecurityFeature: ReducerProtocol {
    public struct State: Equatable {
        var isAuthenticated: Bool = false
        var biometricType: BiometricType = .none
        var encryptionStatus: EncryptionStatus = .idle
        var currentError: SecurityError?
        var auditLog: [AuditEvent] = []
    }
    
    public enum Action: Equatable {
        case checkBiometrics
        case authenticate
        case biometricAuthResult(Result<Bool, SecurityError>)
        case encryptData(Data)
        case decryptData(Data)
        case encryptionComplete(Result<Data, SecurityError>)
        case logEvent(AuditEvent)
        case exportAuditLog
    }
    
    public enum BiometricType: Equatable {
        case none
        case faceID
        case touchID
    }
    
    public enum EncryptionStatus: Equatable {
        case idle
        case encrypting
        case decrypting
        case completed
        case error(String)
    }
    
    public enum SecurityError: Error, Equatable {
        case biometricsNotAvailable
        case authenticationFailed
        case encryptionFailed
        case decryptionFailed
        case keyGenerationFailed
    }
    
    public struct AuditEvent: Equatable {
        let timestamp: Date
        let action: String
        let userIdentifier: String
        let resourceType: String
        let status: String
    }
    
    @Dependency(\.securityManager) var securityManager
    @Dependency(\.auditLogger) var auditLogger
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .checkBiometrics:
                return checkBiometricSupport()
                
            case .authenticate:
                return authenticateUser()
                
            case .biometricAuthResult(.success(let success)):
                state.isAuthenticated = success
                return logAuthenticationEvent(success: success)
                
            case .biometricAuthResult(.failure(let error)):
                state.currentError = error
                return logAuthenticationEvent(success: false)
                
            case .encryptData(let data):
                state.encryptionStatus = .encrypting
                return encryptSensitiveData(data)
                
            case .decryptData(let data):
                state.encryptionStatus = .decrypting
                return decryptSensitiveData(data)
                
            case .encryptionComplete(.success):
                state.encryptionStatus = .completed
                return .none
                
            case .encryptionComplete(.failure(let error)):
                state.encryptionStatus = .error(error.localizedDescription)
                state.currentError = error
                return .none
                
            case .logEvent(let event):
                state.auditLog.append(event)
                return logAuditEvent(event)
                
            case .exportAuditLog:
                return exportAuditLogData()
            }
        }
    }
    
    private func checkBiometricSupport() -> Effect<Action, Never> {
        Effect.task {
            let type = await securityManager.checkBiometricSupport()
            return .biometricAuthResult(.success(type != .none))
        }
    }
    
    private func authenticateUser() -> Effect<Action, Never> {
        Effect.task {
            do {
                let success = try await securityManager.authenticateWithBiometrics()
                return .biometricAuthResult(.success(success))
            } catch {
                return .biometricAuthResult(.failure(.authenticationFailed))
            }
        }
    }
    
    private func encryptSensitiveData(_ data: Data) -> Effect<Action, Never> {
        Effect.task {
            do {
                let encryptedData = try await securityManager.encrypt(data)
                return .encryptionComplete(.success(encryptedData))
            } catch {
                return .encryptionComplete(.failure(.encryptionFailed))
            }
        }
    }
    
    private func decryptSensitiveData(_ data: Data) -> Effect<Action, Never> {
        Effect.task {
            do {
                let decryptedData = try await securityManager.decrypt(data)
                return .encryptionComplete(.success(decryptedData))
            } catch {
                return .encryptionComplete(.failure(.decryptionFailed))
            }
        }
    }
    
    private func logAuthenticationEvent(success: Bool) -> Effect<Action, Never> {
        let event = AuditEvent(
            timestamp: Date(),
            action: "user_authentication",
            userIdentifier: securityManager.currentUserIdentifier,
            resourceType: "system",
            status: success ? "success" : "failure"
        )
        return .send(.logEvent(event))
    }
    
    private func logAuditEvent(_ event: AuditEvent) -> Effect<Action, Never> {
        Effect.task {
            await auditLogger.log(event)
            return .none
        }
    }
    
    private func exportAuditLogData() -> Effect<Action, Never> {
        Effect.task {
            await auditLogger.exportLog()
            return .none
        }
    }
}
