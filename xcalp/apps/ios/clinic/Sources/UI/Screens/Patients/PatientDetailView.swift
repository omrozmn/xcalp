import ComposableArchitecture
import SwiftUI

public struct PatientDetailView: View {
    let store: StoreOf<PatientDetailFeature>
    
    public init(store: StoreOf<PatientDetailFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: 24) {
                    // Patient Info
                    PatientInfoSection(patient: viewStore.patient)
                    
                    // Scans
                    if !viewStore.scans.isEmpty {
                        ScansSection(scans: viewStore.scans)
                    }
                    
                    // Treatments
                    if !viewStore.treatments.isEmpty {
                        TreatmentsSection(treatments: viewStore.treatments)
                    }
                }
                .padding()
            }
            .navigationTitle("Patient Details")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewStore.send(.editButtonTapped)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        viewStore.send(.deleteButtonTapped)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .alert(
                "Error",
                isPresented: viewStore.binding(
                    get: { $0.errorMessage != nil },
                    send: { _ in .setError(nil) }
                ),
                presenting: viewStore.errorMessage
            ) { _ in
                Button("OK") { viewStore.send(.setError(nil)) }
            } message: { message in
                Text(message)
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

private struct PatientInfoSection: View {
    let patient: Patient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Patient Information")
                .xcalpText(.h2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Name: \(patient.name)")
                    .xcalpText(.body)
                Text("Age: \(patient.age)")
                    .xcalpText(.body)
                Text("Last Visit: \(patient.lastVisit.formatted(date: .abbreviated, time: .omitted))")
                    .xcalpText(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(hex: "F5F5F5"))
        .cornerRadius(10)
    }
}

private struct ScansSection: View {
    let scans: [ScanData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scans")
                .xcalpText(.h2)
            
            ForEach(scans) { scan in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.date.formatted(date: .abbreviated, time: .shortened))
                            .xcalpText(.body)
                        Text("Quality: \(Int(scan.quality * 100))%")
                            .xcalpText(.caption)
                        if !scan.notes.isEmpty {
                            Text(scan.notes)
                                .xcalpText(.caption)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(hex: "F5F5F5"))
                .cornerRadius(10)
            }
        }
    }
}

private struct TreatmentsSection: View {
    let treatments: [Treatment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Treatments")
                .xcalpText(.h2)
            
            ForEach(treatments) { treatment in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(treatment.date.formatted(date: .abbreviated, time: .shortened))
                            .xcalpText(.body)
                        Text(treatment.type.rawValue.capitalized)
                            .xcalpText(.caption)
                        Text(treatment.status.rawValue.capitalized)
                            .xcalpText(.caption)
                            .foregroundColor(statusColor(for: treatment.status))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(hex: "F5F5F5"))
                .cornerRadius(10)
            }
        }
    }
    
    private func statusColor(for status: Treatment.TreatmentStatus) -> Color {
        switch status {
        case .scheduled:
            return .blue
        case .inProgress:
            return .orange
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }
}
