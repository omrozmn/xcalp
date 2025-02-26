import SwiftUI
import ComposableArchitecture

public struct PatientRegistrationView: View {
    let store: StoreOf<PatientRegistrationFeature>
    
    public init(store: StoreOf<PatientRegistrationFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("First Name", text: viewStore.binding(
                        get: \.firstName,
                        send: PatientRegistrationFeature.Action.setFirstName
                    ))
                    .textContentType(.givenName)
                    .accessibilityLabel("First name input field")
                    
                    TextField("Last Name", text: viewStore.binding(
                        get: \.lastName,
                        send: PatientRegistrationFeature.Action.setLastName
                    ))
                    .textContentType(.familyName)
                    .accessibilityLabel("Last name input field")
                    
                    DatePicker(
                        "Date of Birth",
                        selection: viewStore.binding(
                            get: \.dateOfBirth,
                            send: PatientRegistrationFeature.Action.setDateOfBirth
                        ),
                        displayedComponents: .date
                    )
                    .accessibilityLabel("Date of birth selector")
                    
                    Picker("Gender", selection: viewStore.binding(
                        get: \.gender,
                        send: PatientRegistrationFeature.Action.setGender
                    )) {
                        ForEach(PatientRegistrationFeature.State.Gender.allCases, id: \.self) { gender in
                            Text(gender.rawValue.capitalized)
                                .tag(gender)
                        }
                    }
                    .accessibilityLabel("Gender selector")
                }
                
                Section(header: Text("Contact Information")) {
                    TextField("Email", text: viewStore.binding(
                        get: \.email,
                        send: PatientRegistrationFeature.Action.setEmail
                    ))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .accessibilityLabel("Email input field")
                    
                    TextField("Phone", text: viewStore.binding(
                        get: \.phone,
                        send: PatientRegistrationFeature.Action.setPhone
                    ))
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .accessibilityLabel("Phone number input field")
                    
                    TextField("Address", text: viewStore.binding(
                        get: \.address,
                        send: PatientRegistrationFeature.Action.setAddress
                    ))
                    .textContentType(.fullStreetAddress)
                    .accessibilityLabel("Address input field")
                }
                
                Section(header: Text("Medical History")) {
                    TextEditor(text: viewStore.binding(
                        get: \.medicalHistory,
                        send: PatientRegistrationFeature.Action.setMedicalHistory
                    ))
                    .frame(height: 100)
                    .accessibilityLabel("Medical history input field")
                }
                
                if !viewStore.validationErrors.isEmpty {
                    Section {
                        ForEach(viewStore.validationErrors, id: \.self) { error in
                            ValidationErrorView(error: error)
                        }
                    }
                }
                
                Section {
                    Button(action: { viewStore.send(.validateFields) }) {
                        if viewStore.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Register Patient")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewStore.isLoading)
                    .accessibilityLabel("Register patient button")
                    .accessibilityHint("Tap to complete patient registration")
                }
            }
            .navigationTitle("New Patient")
            .navigationBarTitleDisplayMode(.large)
            .alert("Registration Complete", isPresented: viewStore.binding(
                get: \.registrationComplete,
                send: { _ in .clearValidationErrors }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Patient has been successfully registered.")
            }
        }
    }
}

private struct ValidationErrorView: View {
    let error: PatientRegistrationFeature.State.ValidationError
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(errorMessage)
                .foregroundColor(.red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Validation error: \(errorMessage)")
    }
    
    private var errorMessage: String {
        switch error {
        case .emptyField(let field):
            return "\(field) is required"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .invalidPhone:
            return "Please enter a valid phone number"
        case .futureDateOfBirth:
            return "Date of birth cannot be in the future"
        }
    }
}