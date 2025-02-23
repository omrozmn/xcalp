import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @EnvironmentObject private var coordinator: AuthenticationCoordinator
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Header
                VStack(spacing: 10) {
                    Text("Create Account")
                        .font(XcalpTypography.title)
                        .foregroundColor(XcalpColors.text)
                    
                    Text("Join the XcalpClinic network")
                        .font(XcalpTypography.body)
                        .foregroundColor(XcalpColors.secondary)
                }
                .padding(.top, 40)
                
                // Form
                VStack(spacing: 20) {
                    // Personal Info
                    Group {
                        TextField("First Name", text: $viewModel.firstName)
                        TextField("Last Name", text: $viewModel.lastName)
                        TextField("Email", text: $viewModel.email)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    // Professional Info
                    Group {
                        TextField("Medical License Number", text: $viewModel.licenseNumber)
                        TextField("Clinic Name", text: $viewModel.clinicName)
                        TextField("Specialty", text: $viewModel.specialty)
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    // Password
                    Group {
                        SecureField("Password", text: $viewModel.password)
                        SecureField("Confirm Password", text: $viewModel.confirmPassword)
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    // Error Message
                    if !viewModel.errorMessage.isEmpty {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                            .font(XcalpTypography.caption)
                    }
                    
                    // Register Button
                    Button(action: { Task { await viewModel.register() }}) {
                        Text("Create Account")
                            .font(XcalpTypography.button)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(XcalpColors.primary)
                            .cornerRadius(10)
                    }
                    .disabled(viewModel.isLoading)
                    
                    // Back to Login
                    Button(action: { coordinator.navigate(to: .login) }) {
                        Text("Already have an account? Sign In")
                            .font(XcalpTypography.caption)
                            .foregroundColor(XcalpColors.primary)
                    }
                }
                .padding(.horizontal, 30)
                
                // Terms and Privacy
                VStack(spacing: 10) {
                    Text("By creating an account, you agree to our")
                        .font(XcalpTypography.caption)
                    
                    HStack(spacing: 5) {
                        Text("Terms of Service")
                            .foregroundColor(XcalpColors.primary)
                        Text("and")
                        Text("Privacy Policy")
                            .foregroundColor(XcalpColors.primary)
                    }
                    .font(XcalpTypography.caption)
                }
                .foregroundColor(XcalpColors.secondary)
                .padding(.top, 20)
            }
            .padding(.bottom, 40)
        }
    }
}
