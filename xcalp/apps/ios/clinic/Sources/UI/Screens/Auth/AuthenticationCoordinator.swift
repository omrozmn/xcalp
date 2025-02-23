import SwiftUI

@MainActor
final class AuthenticationCoordinator: ObservableObject {
    @Published var currentView: AuthenticationView = .login
    @Published var isAuthenticated = false
    
    private let authManager = AuthenticationManager.shared
    
    init() {
        authManager.$isAuthenticated
            .assign(to: &$isAuthenticated)
    }
    
    enum AuthenticationView {
        case login
        case register
        case forgotPassword
    }
    
    func navigate(to view: AuthenticationView) {
        currentView = view
    }
}

struct AuthenticationContainer: View {
    @StateObject private var coordinator = AuthenticationCoordinator()
    
    var body: some View {
        Group {
            if coordinator.isAuthenticated {
                MainTabView()
            } else {
                NavigationView {
                    switch coordinator.currentView {
                    case .login:
                        LoginView()
                    case .register:
                        RegisterView()
                    case .forgotPassword:
                        ForgotPasswordView()
                    }
                }
            }
        }
        .environmentObject(coordinator)
    }
}
