import ComposableArchitecture
import Foundation

public struct ForgotPasswordFeature: Reducer {
    public struct State: Equatable {
        public var email: String
        public var isLoading: Bool
        public var error: ForgotPasswordError?
        public var isResetEmailSent: Bool
        public var resetToken: String?
        public var newPassword: String
        public var confirmPassword: String
        public var isResettingPassword: Bool
        
        public init(
            email: String = "",
            isLoading: Bool = false,
            error: ForgotPasswordError? = nil,
            isResetEmailSent: Bool = false,
            resetToken: String? = nil,
            newPassword: String = "",
            confirmPassword: String = "",
            isResettingPassword: Bool = false
        ) {
            self.email = email
            self.isLoading = isLoading
            self.error = error
            self.isResetEmailSent = isResetEmailSent
            self.resetToken = resetToken
            self.newPassword = newPassword
            self.confirmPassword = confirmPassword
            self.isResettingPassword = isResettingPassword
        }
    }
    
    public enum Action: Equatable {
        case emailChanged(String)
        case sendResetEmailButtonTapped
        case sendResetEmailResponse(TaskResult<String>)
        case resetTokenReceived(String)
        case newPasswordChanged(String)
        case confirmPasswordChanged(String)
        case resetPasswordButtonTapped
        case resetPasswordResponse(TaskResult<Bool>)
        case errorDismissed
        case backToLoginTapped
    }
    
    @Dependency(\.authClient) var authClient
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .emailChanged(email):
                state.email = email
                return .none
                
            case .sendResetEmailButtonTapped:
                state.isLoading = true
                return .run { [email = state.email] send in
                    await send(.sendResetEmailResponse(
                        TaskResult {
                            try await authClient.requestPasswordReset(email: email)
                        }
                    ))
                }
                
            case let .sendResetEmailResponse(.success(token)):
                state.isLoading = false
                state.isResetEmailSent = true
                state.resetToken = token
                return .none
                
            case .sendResetEmailResponse(.failure):
                state.isLoading = false
                state.error = .resetEmailFailed
                return .none
                
            case let .resetTokenReceived(token):
                state.resetToken = token
                return .none
                
            case let .newPasswordChanged(password):
                state.newPassword = password
                return .none
                
            case let .confirmPasswordChanged(password):
                state.confirmPassword = password
                return .none
                
            case .resetPasswordButtonTapped:
                guard state.newPassword == state.confirmPassword else {
                    state.error = .passwordsDoNotMatch
                    return .none
                }
                
                guard let token = state.resetToken else {
                    state.error = .invalidResetToken
                    return .none
                }
                
                state.isResettingPassword = true
                return .run { [password = state.newPassword] send in
                    await send(.resetPasswordResponse(
                        TaskResult {
                            try await authClient.resetPassword(
                                token: token,
                                newPassword: password
                            )
                        }
                    ))
                }
                
            case .resetPasswordResponse(.success):
                state.isResettingPassword = false
                // Navigate back to login
                return .none
                
            case .resetPasswordResponse(.failure):
                state.isResettingPassword = false
                state.error = .resetPasswordFailed
                return .none
                
            case .errorDismissed:
                state.error = nil
                return .none
                
            case .backToLoginTapped:
                // Handle navigation back to login
                return .none
            }
        }
    }
}

public enum ForgotPasswordError: Error, Equatable {
    case resetEmailFailed
    case invalidResetToken
    case passwordsDoNotMatch
    case resetPasswordFailed
    case networkError
}
