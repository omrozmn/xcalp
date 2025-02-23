import SwiftUI

@MainActor
final class PatientEditViewModel: ObservableObject {
    @Published var firstName: String
    @Published var lastName: String
    @Published var dateOfBirth: Date
    @Published var gender: String
    @Published var medicalHistory: String = ""
    @Published var emergencyContactName: String = ""
    @Published var emergencyContactPhone: String = ""
    
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private let patient: Patient
    
    init(patient: Patient) {
        self.patient = patient
        self.firstName = patient.firstName
        self.lastName = patient.lastName
        self.dateOfBirth = patient.dateOfBirth ?? Date()
        self.gender = patient.gender ?? ""
    }
    
    func save() async -> Bool {
        guard validate() else { return false }
        
        isLoading = true
        errorMessage = ""
        
        do {
            // TODO: Save to CoreData
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return true
        } catch {
            errorMessage = "Failed to save changes"
            return false
        }
    }
    
    private func validate() -> Bool {
        if firstName.isEmpty || lastName.isEmpty {
            errorMessage = "Name fields cannot be empty"
            return false
        }
        return true
    }
}
