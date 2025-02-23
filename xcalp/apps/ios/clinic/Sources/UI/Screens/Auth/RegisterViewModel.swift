import Foundation

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var licenseNumber = ""
    @Published var clinicName = ""
    @Published var specialty = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private let authManager = AuthenticationManager.shared
    
    func register() async {
        guard validate() else { return }
        
        isLoading = true
        errorMessage = ""
        
        do {
            // TODO: Implement actual registration API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await authManager.authenticateWithCredentials(email: email, password: password)
        } catch {
            errorMessage = "Registration failed. Please try again."
        }
        
        isLoading = false
    }
    
    private func validate() -> Bool {
        if firstName.isEmpty || lastName.isEmpty {
            errorMessage = "Please enter your full name"
            return false
        }
        
        if email.isEmpty || !email.contains("@") {
            errorMessage = "Please enter a valid email"
            return false
        }
        
        if licenseNumber.isEmpty {
            errorMessage = "Please enter your medical license number"
            return false
        }
        
        if password.isEmpty || password.count < 8 {
            errorMessage = "Password must be at least 8 characters"
            return false
        }
        
        if password != confirmPassword {
            errorMessage = "Passwords do not match"
            return false
        }
        
        return true
    }
}
