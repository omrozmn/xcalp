import SwiftUI

@MainActor
final class PatientDetailViewModel: ObservableObject {
    @Published var scans: [Scan] = []
    @Published var treatments: [Treatment] = []
    @Published var showEditSheet = false
    
    private let patient: Patient
    
    init(patient: Patient) {
        self.patient = patient
        loadPatientData()
    }
    
    private func loadPatientData() {
        // TODO: Load from CoreData
        scans = Array(patient.scans ?? [])
        treatments = Array(patient.treatments ?? [])
    }
    
    func startNewScan() {
        // TODO: Navigate to scan view
    }
    
    func viewTreatmentPlan() {
        // TODO: Navigate to treatment view
    }
}
