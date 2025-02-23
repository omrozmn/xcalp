import SwiftUI

@MainActor
final class AddPatientViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var dateOfBirth = Date()
    @Published var gender = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var medicalHistory = ""
    @Published var emergencyContactName = ""
    @Published var emergencyContactPhone = ""
    
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    func save() async -> Bool {
        guard validate() else { return false }
        
        isLoading = true
        errorMessage = ""
        
        do {
            // TODO: Save to CoreData
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return true
        } catch {
            errorMessage = "Failed to add patient"
            return false
        } finally {
            isLoading = false
        }
    }
    
    private func validate() -> Bool {
        if firstName.isEmpty || lastName.isEmpty {
            errorMessage = "Name fields cannot be empty"
            return false
        }
        
        if email.isEmpty && phone.isEmpty {
            errorMessage = "Please provide either email or phone"
            return false
        }
        
        if !email.isEmpty && !email.contains("@") {
            errorMessage = "Please enter a valid email"
            return false
        }
        
        return true
    }
}
