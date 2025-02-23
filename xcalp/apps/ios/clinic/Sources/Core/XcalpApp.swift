import SwiftUI
import ComposableArchitecture
import FirebaseCore
import FirebaseCrashlytics

@main
struct XcalpApp: App {
    init() {
        setupAppearance()
        setupFirebase()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView(
                store: Store(
                    initialState: RootFeature.State(),
                    reducer: { RootFeature() }
                )
            )
        }
    }
    
    private func setupAppearance() {
        // Configure global appearance settings
        if #available(iOS 15.0, *) {
            let navigationBarAppearance = UINavigationBarAppearance()
            navigationBarAppearance.configureWithOpaqueBackground()
            navigationBarAppearance.backgroundColor = .systemBackground
            UINavigationBar.appearance().standardAppearance = navigationBarAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        }
    }
    
    private func setupFirebase() {
        FirebaseApp.configure()
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }
}

struct RootFeature: Reducer {
    struct State: Equatable {
        var isAuthenticated = false
        var sessionError: String?
    }
    
    enum Action: Equatable {
        case checkSession
        case sessionResponse(TaskResult<Bool>)
        case logout
    }
    
    @Dependency(\.sessionManager) var sessionManager
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .checkSession:
                return .run { send in
                    do {
                        let session = try await sessionManager.getCurrentSession()
                        await send(.sessionResponse(.success(session != nil)))
                    } catch {
                        await send(.sessionResponse(.failure(error)))
                    }
                }
                
            case let .sessionResponse(.success(isAuthenticated)):
                state.isAuthenticated = isAuthenticated
                state.sessionError = nil
                return .none
                
            case let .sessionResponse(.failure(error)):
                state.isAuthenticated = false
                state.sessionError = error.localizedDescription
                return .none
                
            case .logout:
                return .run { _ in
                    try await sessionManager.invalidateSession()
                }
            }
        }
    }
}

struct RootView: View {
    let store: StoreOf<RootFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .task {
                await viewStore.send(.checkSession).finish()
            }
            .alert(
                "Session Error",
                isPresented: .constant(viewStore.sessionError != nil),
                actions: {
                    Button("OK") {
                        viewStore.send(.logout)
                    }
                },
                message: {
                    if let error = viewStore.sessionError {
                        Text(error)
                    }
                }
            )
        }
    }
}
