import SwiftUI

@MainActor
final class PatientListViewModel: ObservableObject {
    @Published var patients: [Patient] = []
    @Published var searchText = ""
    @Published var sortOption = SortOption.name
    @Published var isLoading = false
    
    enum SortOption {
        case name
        case recent
    }
    
    var filteredPatients: [Patient] {
        let filtered = patients.filter { patient in
            if searchText.isEmpty { return true }
            let searchQuery = searchText.lowercased()
            return patient.firstName.lowercased().contains(searchQuery) ||
                   patient.lastName.lowercased().contains(searchQuery)
        }
        
        return filtered.sorted { p1, p2 in
            switch sortOption {
            case .name:
                let name1 = "\(p1.lastName) \(p1.firstName)"
                let name2 = "\(p2.lastName) \(p2.firstName)"
                return name1 < name2
            case .recent:
                let date1 = (p1.treatments?.first?.createdAt ?? p1.scans?.first?.createdAt) ?? Date.distantPast
                let date2 = (p2.treatments?.first?.createdAt ?? p2.scans?.first?.createdAt) ?? Date.distantPast
                return date1 > date2
            }
        }
    }
    
    func loadPatients() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // TODO: Load from CoreData
            try await Task.sleep(nanoseconds: 1_000_000_000)
            // Placeholder data
            patients = [
                Patient(
                    firstName: "John",
                    lastName: "Doe",
                    dateOfBirth: Date(),
                    gender: .male
                ),
                Patient(
                    firstName: "Jane",
                    lastName: "Smith",
                    dateOfBirth: Date(),
                    gender: .female
                )
            ]
        } catch {
            print("Failed to load patients: \(error)")
        }
    }
}
