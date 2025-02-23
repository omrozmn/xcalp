import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var viewModel = ForgotPasswordViewModel()
    @EnvironmentObject private var coordinator: AuthenticationCoordinator
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 15) {
                Text("Reset Password")
                    .font(XcalpTypography.title)
                    .foregroundColor(XcalpColors.text)
                
                Text("Enter your email to receive reset instructions")
                    .font(XcalpTypography.body)
                    .foregroundColor(XcalpColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 60)
            
            // Form
            VStack(spacing: 20) {
                TextField("Email", text: $viewModel.email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                
                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(XcalpTypography.caption)
                }
                
                if viewModel.isSuccess {
                    Text("Check your email for reset instructions")
                        .foregroundColor(.green)
                        .font(XcalpTypography.body)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: { Task { await viewModel.resetPassword() }}) {
                    Text("Send Reset Link")
                        .font(XcalpTypography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(XcalpColors.primary)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isLoading)
                
                Button(action: { coordinator.navigate(to: .login) }) {
                    Text("Back to Sign In")
                        .font(XcalpTypography.caption)
                        .foregroundColor(XcalpColors.primary)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            // Footer
            Text("Need help? Contact support")
                .font(XcalpTypography.caption)
                .foregroundColor(XcalpColors.secondary)
                .padding(.bottom, 20)
        }
    }
}
