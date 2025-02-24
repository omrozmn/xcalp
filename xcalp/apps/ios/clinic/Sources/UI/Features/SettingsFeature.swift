import ComposableArchitecture
import Foundation

public struct SettingsFeature: Reducer {
    public struct State: Equatable {
        public var userProfile: UserProfile
        public var preferences: Preferences
        public var isLoading: Bool
        public var errorMessage: String?
        
        public init(
            userProfile: UserProfile = .init(),
            preferences: Preferences = .init(),
            isLoading: Bool = false,
            errorMessage: String? = nil
        ) {
            self.userProfile = userProfile
            self.preferences = preferences
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }
    
    public struct UserProfile: Equatable {
        public var name: String
        public var email: String
        public var role: UserRole
        
        public init(
            name: String = "",
            email: String = "",
            role: UserRole = .clinician
        ) {
            self.name = name
            self.email = email
            self.role = role
        }
    }
    
    public enum UserRole: String, CaseIterable {
        case admin = "Administrator"
        case clinician = "Clinician"
        case assistant = "Assistant"
    }
    
    public struct Preferences: Equatable {
        public var useBiometrics: Bool
        public var darkMode: Bool
        public var notifications: Bool
        
        public init(
            useBiometrics: Bool = true,
            darkMode: Bool = false,
            notifications: Bool = true
        ) {
            self.useBiometrics = useBiometrics
            self.darkMode = darkMode
            self.notifications = notifications
        }
    }
    
    public enum Action: Equatable {
        case loadSettings
        case updateProfile(UserProfile)
        case updatePreferences(Preferences)
        case setError(String?)
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadSettings:
                state.isLoading = true
                state.errorMessage = nil
                return .none
                
            case let .updateProfile(profile):
                state.userProfile = profile
                state.isLoading = false
                return .none
                
            case let .updatePreferences(preferences):
                state.preferences = preferences
                return .none
                
            case let .setError(error):
                state.errorMessage = error
                state.isLoading = false
                return .none
            }
        }
    }
}
