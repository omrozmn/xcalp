import ComposableArchitecture
import Core
import CoreImage
import Foundation

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
        public var mfaSetupData: MFASetupResponse?
        public var mfaQRCode: CIImage?
        public var showRecoveryCodes: Bool
        public var recoveryCodes: [String]
        
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
            mfaPendingID: String? = nil,
            mfaSetupData: MFASetupResponse? = nil,
            mfaQRCode: CIImage? = nil,
            showRecoveryCodes: Bool = false,
            recoveryCodes: [String] = []
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
            self.mfaSetupData = mfaSetupData
            self.mfaQRCode = mfaQRCode
            self.showRecoveryCodes = showRecoveryCodes
            self.recoveryCodes = recoveryCodes
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
        case setupMFATapped
        case setupMFAResponse(TaskResult<MFASetupResponse>)
        case generateQRCode(String)
        case generateQRCodeResponse(TaskResult<CIImage>)
        case verifyMFAButtonTapped
        case verifyMFAResponse(TaskResult<AuthResponse>)
        case generateNewRecoveryCodesTapped
        case generateNewRecoveryCodesResponse(TaskResult<[String]>)
        case showRecoveryCodesTapped
        case hideRecoveryCodesTapped
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
                
            case .setupMFATapped:
                state.isLoading = true
                return .run { send in
                    await send(.setupMFAResponse(
                        TaskResult {
                            try await authClient.setupMFA(.authenticatorApp)
                        }
                    ))
                }
                
            case let .setupMFAResponse(.success(response)):
                state.isLoading = false
                state.mfaSetupData = response
                state.recoveryCodes = response.recoveryCodes
                state.showRecoveryCodes = true
                return .run { send in
                    await send(.generateQRCode(response.otpAuthURL))
                }
                
            case let .setupMFAResponse(.failure(error)):
                state.isLoading = false
                state.error = .loginFailed(error)
                return .none
                
            case let .generateQRCode(url):
                return .run { send in
                    await send(.generateQRCodeResponse(
                        TaskResult {
                            try authClient.generateQRCode(url)
                        }
                    ))
                }
                
            case let .generateQRCodeResponse(.success(qrCode)):
                state.mfaQRCode = qrCode
                return .none
                
            case let .generateQRCodeResponse(.failure(error)):
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
                state.mfaSetupData = nil
                state.mfaQRCode = nil
                state.showRecoveryCodes = false
                return .none
                
            case let .verifyMFAResponse(.failure(error)):
                state.isLoading = false
                state.error = .mfaFailed
                return .none
                
            case .generateNewRecoveryCodesTapped:
                state.isLoading = true
                return .run { send in
                    await send(.generateNewRecoveryCodesResponse(
                        TaskResult {
                            try await authClient.generateNewRecoveryCodes()
                        }
                    ))
                }
                
            case let .generateNewRecoveryCodesResponse(.success(codes)):
                state.isLoading = false
                state.recoveryCodes = codes
                state.showRecoveryCodes = true
                return .none
                
            case let .generateNewRecoveryCodesResponse(.failure(error)):
                state.isLoading = false
                state.error = .loginFailed(error)
                return .none
                
            case .showRecoveryCodesTapped:
                state.showRecoveryCodes = true
                return .none
                
            case .hideRecoveryCodesTapped:
                state.showRecoveryCodes = false
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
                return .none
                
            case .logoutButtonTapped:
                state.isAuthenticated = false
                state.username = ""
                state.password = ""
                state.mfaCode = ""
                state.mfaSetupData = nil
                state.mfaQRCode = nil
                state.showRecoveryCodes = false
                state.recoveryCodes = []
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

public struct MFASetupResponse: Equatable {
    public let otpAuthURL: String
    public let recoveryCodes: [String]
}
