
import SwiftUI
import ComposableArchitecture

public struct LoginView: View {
    let store: StoreOf<AuthFeature>
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password, mfaCode
    }
    
    public init(store: StoreOf<AuthFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationView {
                ScrollView {
                    VStack(spacing: 24) {
                        // Logo and Welcome Text
                        Image("XcalpLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .padding(.top, 60)
                        
                        Text("Welcome Back")
                            .xcalpText(.h1)
                            .padding(.bottom, 8)
                        
                        Text("Sign in to continue")
                            .xcalpText(.body)
                            .padding(.bottom, 32)
                        
                        if viewStore.requiresMFA {
                            // MFA Input
                            VStack(spacing: 16) {
                                Text("Enter Verification Code")
                                    .xcalpText(.h2)
                                    .padding(.bottom, 8)
                                
                                Text("Please enter the verification code from your authenticator app")
                                    .xcalpText(.body)
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom, 16)
                                
                                TextField("Verification Code", text: viewStore.binding(
                                    get: \.mfaCode,
                                    send: AuthFeature.Action.mfaCodeChanged
                                ))
                                .xcalpTextField()
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .mfaCode)
                                
                                XcalpButton(
                                    title: "Verify",
                                    isLoading: viewStore.isLoading
                                ) {
                                    viewStore.send(.verifyMFAButtonTapped)
                                }
                            }
                        } else {
                            // Login Fields
                            VStack(spacing: 16) {
                                TextField("Email", text: viewStore.binding(
                                    get: \.username,
                                    send: AuthFeature.Action.usernameChanged
                                ))
                                .xcalpTextField()
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                
                                SecureField("Password", text: viewStore.binding(
                                    get: \.password,
                                    send: AuthFeature.Action.passwordChanged
                                ))
                                .xcalpTextField()
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                            }
                            .padding(.bottom, 24)
                            
                            // Forgot Password
                            Button("Forgot Password?") {
                                viewStore.send(.forgotPasswordTapped)
                            }
                            .xcalpText(.caption)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, 32)
                            
                            // Sign In Button
                            XcalpButton(
                                title: "Sign In",
                                isLoading: viewStore.isLoading
                            ) {
                                viewStore.send(.loginButtonTapped)
                            }
                            
                            if viewStore.biometricType != .none {
                                Button {
                                    viewStore.send(.biometricAuthTapped)
                                } label: {
                                    Image(systemName: viewStore.biometricType == .faceID ? "faceid" : "touchid")
                                        .font(.title)
                                        .foregroundColor(.accentColor)
                                }
                                .padding(.top, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .alert(
                    "Error",
                    isPresented: viewStore.binding(
                        get: { $0.error != nil },
                        send: AuthFeature.Action.errorDismissed
                    ),
                    presenting: viewStore.error
                ) { _ in
                    Button("OK") { viewStore.send(.errorDismissed) }
                } message: { error in
                    Text(error.localizedDescription)
                }
            }
        }
    }
}
