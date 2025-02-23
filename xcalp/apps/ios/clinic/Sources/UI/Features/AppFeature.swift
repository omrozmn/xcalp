import Foundation
import ComposableArchitecture

public struct AppFeature: Reducer {
    public struct State: Equatable {
        public var auth: AuthenticationFeature.State
        public var mainApp: MainAppFeature.State?
        
        public init(
            auth: AuthenticationFeature.State = .init(),
            mainApp: MainAppFeature.State? = nil
        ) {
            self.auth = auth
            self.mainApp = mainApp
        }
    }
    
    public enum Action: Equatable {
        case auth(AuthenticationFeature.Action)
        case mainApp(MainAppFeature.Action)
        case authenticationSucceeded
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .auth(.loginSucceeded):
                state.mainApp = MainAppFeature.State()
                return .send(.authenticationSucceeded)
                
            case .auth:
                return .none
                
            case .mainApp:
                return .none
                
            case .authenticationSucceeded:
                return .none
            }
        }
        
        Scope(state: \.auth, action: /Action.auth) {
            AuthenticationFeature()
        }
        
        OptionalScope(state: \.mainApp, action: /Action.mainApp) {
            MainAppFeature()
        }
    }
}
