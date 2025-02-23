import Foundation
import ComposableArchitecture

public struct AuthFeature: Reducer {
    public struct State: Equatable {
        public var username: String
        public var password: String
        public var mfaCode: String
        public var isLoading: Bool
        public var error: AuthError?
        public var isAuthenticated: Bool
        public var biometricType: BiometricType
        public var isBiometricEnabled: Bool
        public var requiresMFA: Bool
        public var mfaPendingID: String?
        
        public init(
            username: String = "",
            password: String = "",
            mfaCode: String = "",
            isLoading: Bool = false,
            error: AuthError? = nil,
            isAuthenticated: Bool = false,
            biometricType: BiometricType = .none,
            isBiometricEnabled: Bool = false,
            requiresMFA: Bool = false,
            mfaPendingID: String? = nil
        ) {
            self.username = username
            self.password = password
            self.mfaCode = mfaCode
            self.isLoading = isLoading
            self.error = error
            self.isAuthenticated = isAuthenticated
            self.biometricType = biometricType
            self.isBiometricEnabled = isBiometricEnabled
            self.requiresMFA = requiresMFA
            self.mfaPendingID = mfaPendingID
        }
    }
    
    public enum Action: Equatable {
        case usernameChanged(String)
        case passwordChanged(String)
        case mfaCodeChanged(String)
        case loginButtonTapped
        case loginResponse(TaskResult<AuthResponse>)
        case checkBiometricSupport
        case biometricAuthTapped
        case biometricAuthResponse(TaskResult<Bool>)
        case verifyMFAButtonTapped
        case verifyMFAResponse(TaskResult<AuthResponse>)
        case forgotPasswordTapped
        case logoutButtonTapped
        case errorDismissed
    }
    
    @Dependency(\.authClient) var authClient
    @Dependency(\.biometricAuth) var biometricAuth
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .usernameChanged(username):
                state.username = username
                return .none
                
            case let .passwordChanged(password):
                state.password = password
                return .none
                
            case let .mfaCodeChanged(code):
                state.mfaCode = code
                return .none
                
            case .loginButtonTapped:
                state.isLoading = true
                return .run { [username = state.username, password = state.password] send in
                    await send(.loginResponse(
                        TaskResult {
                            try await authClient.login(username: username, password: password)
                        }
                    ))
                }
                
            case let .loginResponse(.success(response)):
                state.isLoading = false
                
                if response.requiresMFA {
                    state.requiresMFA = true
                    state.mfaPendingID = response.mfaPendingID
                    return .none
                }
                
                state.isAuthenticated = true
                
                if state.isBiometricEnabled {
                    return .run { [username = state.username, password = state.password] _ in
                        try await authClient.saveCredentials(username: username, password: password)
                    }
                }
                return .none
                
            case let .loginResponse(.failure(error)):
                state.isLoading = false
                state.error = .loginFailed(error)
                return .none
                
            case .verifyMFAButtonTapped:
                state.isLoading = true
                return .run { [code = state.mfaCode] send in
                    await send(.verifyMFAResponse(
                        TaskResult {
                            try await authClient.verifyMFA(code)
                        }
                    ))
                }
                
            case let .verifyMFAResponse(.success(response)):
                state.isLoading = false
                state.isAuthenticated = true
                state.requiresMFA = false
                state.mfaPendingID = nil
                return .none
                
            case let .verifyMFAResponse(.failure(error)):
                state.isLoading = false
                state.error = .mfaFailed
                return .none
                
            case .checkBiometricSupport:
                return .run { send in
                    let type = await biometricAuth.checkBiometricSupport()
                    if type != .none {
                        let hasCredentials = try await authClient.hasSavedCredentials()
                        if hasCredentials {
                            await send(.biometricAuthTapped)
                        }
                    }
                }
                
            case .biometricAuthTapped:
                state.isLoading = true
                return .run { send in
                    await send(.biometricAuthResponse(
                        TaskResult {
                            try await biometricAuth.authenticate()
                        }
                    ))
                }
                
            case .biometricAuthResponse(.success(true)):
                state.isLoading = false
                return .run { send in
                    let credentials = try await authClient.getSavedCredentials()
                    await send(.loginResponse(
                        TaskResult {
                            try await authClient.login(
                                username: credentials.username,
                                password: credentials.password
                            )
                        }
                    ))
                }
                
            case .biometricAuthResponse(.success(false)):
                state.isLoading = false
                state.error = .biometricAuthFailed
                return .none
                
            case .biometricAuthResponse(.failure):
                state.isLoading = false
                state.error = .biometricAuthFailed
                return .none
                
            case .forgotPasswordTapped:
                // Handle navigation to forgot password
                return .none
                
            case .logoutButtonTapped:
                state.isAuthenticated = false
                state.username = ""
                state.password = ""
                return .run { _ in
                    try await authClient.logout()
                }
                
            case .errorDismissed:
                state.error = nil
                return .none
            }
        }
    }
}

public enum AuthError: Error, Equatable {
    case loginFailed(Error)
    case biometricAuthFailed
    case credentialsNotFound
    case networkError
    case mfaFailed
    
    public static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

public struct AuthResponse: Equatable {
    public let token: String
    public let refreshToken: String
    public let expiresIn: TimeInterval
    public let requiresMFA: Bool
    public let mfaPendingID: String?
}

public enum BiometricType {
    case none
    case faceID
    case touchID
}

public struct Credentials: Equatable {
    public let username: String
    public let password: String
}
