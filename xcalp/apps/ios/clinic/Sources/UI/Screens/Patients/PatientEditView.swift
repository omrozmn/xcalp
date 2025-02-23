import SwiftUI

struct PatientEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PatientEditViewModel
    
    init(patient: Patient) {
        self._viewModel = StateObject(wrappedValue: PatientEditViewModel(patient: patient))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("First Name", text: $viewModel.firstName)
                    TextField("Last Name", text: $viewModel.lastName)
                    DatePicker("Date of Birth",
                             selection: $viewModel.dateOfBirth,
                             displayedComponents: .date)
                    Picker("Gender", selection: $viewModel.gender) {
                        Text("Not Specified").tag("")
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Other").tag("other")
                    }
                }
                
                Section(header: Text("Medical History")) {
                    TextEditor(text: $viewModel.medicalHistory)
                        .frame(height: 100)
                }
                
                Section(header: Text("Emergency Contact")) {
                    TextField("Name", text: $viewModel.emergencyContactName)
                    TextField("Phone", text: $viewModel.emergencyContactPhone)
                }
                
                if !viewModel.errorMessage.isEmpty {
                    Section {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }
}
