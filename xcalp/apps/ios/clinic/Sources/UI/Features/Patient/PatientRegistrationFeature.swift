import ComposableArchitecture
import Foundation

public struct PatientRegistrationFeature: Reducer {
    public struct State: Equatable {
        var firstName: String = ""
        var lastName: String = ""
        var dateOfBirth: Date = Date()
        var gender: Gender = .notSpecified
        var email: String = ""
        var phone: String = ""
        var address: String = ""
        var medicalHistory: String = ""
        var isLoading: Bool = false
        var validationErrors: [ValidationError] = []
        var registrationComplete: Bool = false
        
        public init() {}
        
        public enum Gender: String, CaseIterable {
            case male
            case female
            case other
            case notSpecified
        }
        
        public enum ValidationError: Equatable {
            case emptyField(String)
            case invalidEmail
            case invalidPhone
            case futureDateOfBirth
        }
    }
    
    public enum Action: Equatable {
        case setFirstName(String)
        case setLastName(String)
        case setDateOfBirth(Date)
        case setGender(State.Gender)
        case setEmail(String)
        case setPhone(String)
        case setAddress(String)
        case setMedicalHistory(String)
        case validateFields
        case registerPatient
        case registrationResponse(TaskResult<Patient>)
        case clearValidationErrors
    }
    
    @Dependency(\.patientService) var patientService
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setFirstName(name):
                state.firstName = name
                return .send(.clearValidationErrors)
                
            case let .setLastName(name):
                state.lastName = name
                return .send(.clearValidationErrors)
                
            case let .setDateOfBirth(date):
                state.dateOfBirth = date
                return .send(.clearValidationErrors)
                
            case let .setGender(gender):
                state.gender = gender
                return .send(.clearValidationErrors)
                
            case let .setEmail(email):
                state.email = email
                return .send(.clearValidationErrors)
                
            case let .setPhone(phone):
                state.phone = phone
                return .send(.clearValidationErrors)
                
            case let .setAddress(address):
                state.address = address
                return .send(.clearValidationErrors)
                
            case let .setMedicalHistory(history):
                state.medicalHistory = history
                return .send(.clearValidationErrors)
                
            case .validateFields:
                state.validationErrors = []
                
                // Required fields
                if state.firstName.isEmpty {
                    state.validationErrors.append(.emptyField("First Name"))
                }
                if state.lastName.isEmpty {
                    state.validationErrors.append(.emptyField("Last Name"))
                }
                
                // Email validation
                if !state.email.isEmpty && !isValidEmail(state.email) {
                    state.validationErrors.append(.invalidEmail)
                }
                
                // Phone validation
                if !state.phone.isEmpty && !isValidPhone(state.phone) {
                    state.validationErrors.append(.invalidPhone)
                }
                
                // Date of birth validation
                if state.dateOfBirth > Date() {
                    state.validationErrors.append(.futureDateOfBirth)
                }
                
                return state.validationErrors.isEmpty ? .send(.registerPatient) : .none
                
            case .registerPatient:
                state.isLoading = true
                
                return .run { [state] send in
                    await send(.registrationResponse(TaskResult {
                        try await patientService.registerPatient(
                            firstName: state.firstName,
                            lastName: state.lastName,
                            dateOfBirth: state.dateOfBirth,
                            gender: state.gender,
                            email: state.email,
                            phone: state.phone,
                            address: state.address,
                            medicalHistory: state.medicalHistory
                        )
                    }))
                }
                
            case let .registrationResponse(.success(patient)):
                state.isLoading = false
                state.registrationComplete = true
                return .none
                
            case .registrationResponse(.failure):
                state.isLoading = false
                return .none
                
            case .clearValidationErrors:
                state.validationErrors = []
                return .none
            }
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidPhone(_ phone: String) -> Bool {
        let phoneRegex = "^[+]?[(]?[0-9]{3}[)]?[-\\s.]?[0-9]{3}[-\\s.]?[0-9]{4,6}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phonePredicate.evaluate(with: phone)
    }
}