import Foundation

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    @Published var email = ""
    @Published var errorMessage = ""
    @Published var isLoading = false
    @Published var isSuccess = false
    
    func resetPassword() async {
        guard validate() else { return }
        
        isLoading = true
        errorMessage = ""
        
        do {
            // TODO: Implement actual password reset API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            isSuccess = true
        } catch {
            errorMessage = "Failed to send reset link. Please try again."
        }
        
        isLoading = false
    }
    
    private func validate() -> Bool {
        if email.isEmpty || !email.contains("@") {
            errorMessage = "Please enter a valid email"
            return false
        }
        return true
    }
}
