import ComposableArchitecture
import Core
import SwiftUI

public struct LoginView: View {
    let store: StoreOf<AuthFeature>
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case username
        case password
        case mfaCode
    }
    
    public init(store: StoreOf<AuthFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: 24) {
                    AppLogo()
                        .frame(width: 120, height: 120)
                        .padding(.top, 48)
                    
                    if viewStore.requiresMFA {
                        mfaVerificationView(viewStore)
                    } else if viewStore.showRecoveryCodes {
                        recoveryCodesView(viewStore)
                    } else {
                        loginFieldsView(viewStore)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .onAppear {
                viewStore.send(.checkBiometricSupport)
            }
            .alert(
                "Error",
                isPresented: .init(
                    get: { viewStore.error != nil },
                    set: { _ in viewStore.send(.errorDismissed) }
                ),
                actions: {
                    Button("OK") {
                        viewStore.send(.errorDismissed)
                    }
                },
                message: {
                    if let error = viewStore.error {
                        Text(error.localizedDescription)
                    }
                }
            )
        }
    }
    
    private func loginFieldsView(_ viewStore: ViewStore<AuthFeature.State, AuthFeature.Action>) -> some View {
        VStack(spacing: 16) {
            TextField("Email", text: viewStore.binding(
                get: \.username,
                send: AuthFeature.Action.usernameChanged
            ))
            .xcalpTextField()
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .focused($focusedField, equals: .username)
            
            SecureField("Password", text: viewStore.binding(
                get: \.password,
                send: AuthFeature.Action.passwordChanged
            ))
            .xcalpTextField()
            .textContentType(.password)
            .focused($focusedField, equals: .password)
            
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
                    HStack {
                        Image(systemName: viewStore.biometricType == .faceID ? "faceid" : "touchid")
                        Text("Sign in with \(viewStore.biometricType == .faceID ? "Face ID" : "Touch ID")")
                    }
                }
                .buttonStyle(.plain)
            }
            
            Button("Forgot Password?") {
                viewStore.send(.forgotPasswordTapped)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func mfaVerificationView(_ viewStore: ViewStore<AuthFeature.State, AuthFeature.Action>) -> some View {
        VStack(spacing: 16) {
            Text("Two-Factor Authentication")
                .xcalpText(.h2)
                .padding(.bottom, 8)
            
            Text("Enter the verification code from your authenticator app")
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
            
            if let mfaSetupData = viewStore.mfaSetupData,
               let qrCode = viewStore.mfaQRCode {
                VStack(spacing: 16) {
                    Image(uiImage: UIImage(ciImage: qrCode))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                    
                    Text("Secret Key:")
                        .xcalpText(.caption1)
                    Text(mfaSetupData.secret)
                        .xcalpText(.body)
                        .monospaced()
                }
            }
            
            Button("Use Recovery Code") {
                viewStore.send(.showRecoveryCodesTapped)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func recoveryCodesView(_ viewStore: ViewStore<AuthFeature.State, AuthFeature.Action>) -> some View {
        VStack(spacing: 16) {
            Text("Recovery Codes")
                .xcalpText(.h2)
                .padding(.bottom, 8)
            
            Text("Save these recovery codes in a secure place. You'll need them if you lose access to your authenticator app.")
                .xcalpText(.body)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewStore.recoveryCodes, id: \.self) { code in
                        HStack {
                            Text(code)
                                .xcalpText(.body)
                                .monospaced()
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = code
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 200)
            
            XcalpButton(
                title: "Generate New Codes",
                style: .secondary,
                isLoading: viewStore.isLoading
            ) {
                viewStore.send(.generateNewRecoveryCodesTapped)
            }
            
            XcalpButton(
                title: "Done",
                isLoading: false
            ) {
                viewStore.send(.hideRecoveryCodesTapped)
            }
        }
    }
}

private struct AppLogo: View {
    var body: some View {
        Image("AppLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
