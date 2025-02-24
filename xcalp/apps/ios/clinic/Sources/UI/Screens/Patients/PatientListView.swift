import ComposableArchitecture
import SwiftUI

public struct PatientListView: View {
    let store: StoreOf<PatientListFeature>
    
    public init(store: StoreOf<PatientListFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationView {
                VStack {
                    // Search bar with RTL support
                    TextField(LocalizedStringKey.patientsSearch, text: viewStore.binding(
                        get: \.searchQuery,
                        send: PatientListFeature.Action.setSearchQuery
                    ))
                    .xcalpTextField()
                    .rtlPadding(leading: 16, trailing: 16)
                    .accessibility(label: Text("Search field"))
                    .accessibility(hint: Text("Enter patient name to search"))
                    
                    if viewStore.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibility(label: Text("Loading patients"))
                    } else {
                        List {
                            ForEach(viewStore.patients) { patient in
                                PatientRow(patient: patient)
                                    .accessibilityElement(children: .combine)
                                    .accessibility(label: Text("Patient \(patient.name)"))
                                    .accessibility(hint: Text("Tap for patient details"))
                                    .accessibility(addTraits: .isButton)
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            viewStore.send(.loadPatients)
                        }
                    }
                }
                .navigationTitle(LocalizedStringKey.patientsTitle)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .accessibility(label: Text(LocalizedStringKey.patientsAdd))
                        }
                    }
                }
                .alert(
                    LocalizedStringKey.error,
                    isPresented: viewStore.binding(
                        get: { $0.errorMessage != nil },
                        send: { _ in .setError(nil) }
                    ),
                    presenting: viewStore.errorMessage
                ) { _ in
                    Button(LocalizedStringKey.ok) { viewStore.send(.setError(nil)) }
                } message: { message in
                    Text(message)
                }
            }
            .onAppear {
                viewStore.send(.loadPatients)
            }
            .environment(\.layoutDirection, LayoutHelper.layoutDirection)
        }
    }
}

private struct PatientRow: View {
    let patient: PatientListFeature.Patient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.name)
                .xcalpText(.h3)
                .rtlAlignment()
            
            HStack {
                Text(LocalizedStringKey.patientsAge(patient.age))
                    .xcalpText(.caption)
                
                Spacer()
                
                Text(LocalizedStringKey.patientsLastVisit(patient.lastVisit.formatted(date: .abbreviated, time: .omitted)))
                    .xcalpText(.caption)
            }
            .rtlPadding()
        }
        .padding(.vertical, 8)
        .dynamicallyScaled(height: 80)
    }
}
