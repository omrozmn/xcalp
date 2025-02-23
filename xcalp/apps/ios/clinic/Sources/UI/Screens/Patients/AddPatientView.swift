import SwiftUI

struct AddPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddPatientViewModel()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Required Information")) {
                    TextField("First Name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                    TextField("Last Name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                    DatePicker("Date of Birth",
                             selection: $viewModel.dateOfBirth,
                             displayedComponents: .date)
                }
                
                Section(header: Text("Additional Information")) {
                    Picker("Gender", selection: $viewModel.gender) {
                        Text("Not Specified").tag("")
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Other").tag("other")
                    }
                    
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    
                    TextField("Phone", text: $viewModel.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Medical History")) {
                    TextEditor(text: $viewModel.medicalHistory)
                        .frame(height: 100)
                }
                
                Section(header: Text("Emergency Contact")) {
                    TextField("Name", text: $viewModel.emergencyContactName)
                        .textContentType(.name)
                    TextField("Phone", text: $viewModel.emergencyContactPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                
                if !viewModel.errorMessage.isEmpty {
                    Section {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
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
