import ComposableArchitecture
import SwiftUI

struct LoginFeature: Reducer {
    struct State: Equatable {
        var username = ""
        var password = ""
        var isLoading = false
        var error: String?
    }
    
    enum Action: Equatable {
        case usernameChanged(String)
        case passwordChanged(String)
        case loginTapped
        case loginResponse(TaskResult<Bool>)
    }
    
    @Dependency(\.sessionManager) var sessionManager
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .usernameChanged(username):
                state.username = username
                return .none
                
            case let .passwordChanged(password):
                state.password = password
                return .none
                
            case .loginTapped:
                state.isLoading = true
                state.error = nil
                return .run { [username = state.username] send in
                    do {
                        try await sessionManager.createSession(userId: username)
                        await send(.loginResponse(.success(true)))
                    } catch {
                        await send(.loginResponse(.failure(error)))
                    }
                }
                
            case .loginResponse(.success):
                state.isLoading = false
                return .none
                
            case let .loginResponse(.failure(error)):
                state.isLoading = false
                state.error = error.localizedDescription
                return .none
            }
        }
    }
}

struct LoginView: View {
    let store: StoreOf<LoginFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 20) {
                Text("Welcome to XcalpClinic")
                    .font(.title)
                    .padding(.top, 50)
                
                TextField("Username", text: viewStore.binding(
                    get: \.username,
                    send: LoginFeature.Action.usernameChanged
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                
                SecureField("Password", text: viewStore.binding(
                    get: \.password,
                    send: LoginFeature.Action.passwordChanged
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if let error = viewStore.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: { viewStore.send(.loginTapped) }) {
                    if viewStore.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Login")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewStore.isLoading || viewStore.username.isEmpty || viewStore.password.isEmpty)
                
                Spacer()
            }
            .padding()
        }
    }
}
