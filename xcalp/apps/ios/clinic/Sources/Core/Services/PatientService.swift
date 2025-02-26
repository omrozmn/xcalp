import Foundation
import CoreData

public actor PatientService {
    private let secureStorage: SecureStorageService
    private let analytics: AnalyticsService
    private let errorHandler: ErrorHandler
    private let hipaaLogger: HIPAALogger
    
    init(
        secureStorage: SecureStorageService = .shared,
        analytics: AnalyticsService = .shared,
        errorHandler: ErrorHandler = .shared,
        hipaaLogger: HIPAALogger = .shared
    ) {
        self.secureStorage = secureStorage
        self.analytics = analytics
        self.errorHandler = errorHandler
        self.hipaaLogger = hipaaLogger
    }
    
    public func registerPatient(
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        gender: PatientRegistrationFeature.State.Gender,
        email: String,
        phone: String,
        address: String,
        medicalHistory: String
    ) async throws -> Patient {
        // Log HIPAA event for new patient registration
        await hipaaLogger.log(
            event: .patientRegistration,
            details: [
                "action": "Patient Registration Initiated",
                "identifier": "\(firstName) \(lastName)"
            ]
        )
        
        // Create patient record with secure data handling
        let patient = try await secureStorage.performSecureOperation {
            let patient = Patient(context: secureStorage.mainContext)
            patient.id = UUID()
            patient.firstName = firstName
            patient.lastName = lastName
            patient.dateOfBirth = dateOfBirth
            patient.gender = gender.rawValue
            patient.email = email
            patient.phone = phone
            patient.address = address
            patient.medicalHistory = medicalHistory
            patient.createdAt = Date()
            patient.updatedAt = Date()
            return patient
        }
        
        do {
            // Save with encryption
            try await secureStorage.saveSecurely()
            
            // Log successful registration
            await hipaaLogger.log(
                event: .patientRegistration,
                details: [
                    "action": "Patient Registration Complete",
                    "patientId": patient.id.uuidString,
                    "status": "success"
                ]
            )
            
            // Track analytics
            analytics.track(
                event: .patientRegistered,
                properties: [
                    "patientId": patient.id.uuidString,
                    "hasEmail": !email.isEmpty,
                    "hasPhone": !phone.isEmpty,
                    "hasMedicalHistory": !medicalHistory.isEmpty
                ]
            )
            
            return patient
        } catch {
            // Log registration failure
            await hipaaLogger.log(
                event: .patientRegistration,
                details: [
                    "action": "Patient Registration Failed",
                    "error": error.localizedDescription,
                    "status": "failed"
                ]
            )
            
            // Handle and transform error
            throw errorHandler.handle(
                error,
                context: [
                    "action": "patientRegistration",
                    "patientId": patient.id.uuidString
                ]
            )
        }
    }
    
    public func updatePatient(_ patient: Patient, with updates: [PatientField: Any]) async throws {
        await hipaaLogger.log(
            event: .patientUpdate,
            details: [
                "action": "Patient Update Initiated",
                "patientId": patient.id.uuidString,
                "fields": updates.keys.map { $0.rawValue }
            ]
        )
        
        try await secureStorage.performSecureOperation {
            updates.forEach { field, value in
                switch field {
                case .firstName:
                    patient.firstName = value as? String ?? patient.firstName
                case .lastName:
                    patient.lastName = value as? String ?? patient.lastName
                case .dateOfBirth:
                    patient.dateOfBirth = value as? Date ?? patient.dateOfBirth
                case .gender:
                    patient.gender = value as? String ?? patient.gender
                case .email:
                    patient.email = value as? String ?? patient.email
                case .phone:
                    patient.phone = value as? String ?? patient.phone
                case .address:
                    patient.address = value as? String ?? patient.address
                case .medicalHistory:
                    patient.medicalHistory = value as? String ?? patient.medicalHistory
                }
            }
            patient.updatedAt = Date()
        }
        
        do {
            try await secureStorage.saveSecurely()
            
            await hipaaLogger.log(
                event: .patientUpdate,
                details: [
                    "action": "Patient Update Complete",
                    "patientId": patient.id.uuidString,
                    "status": "success"
                ]
            )
            
            analytics.track(
                event: .patientUpdated,
                properties: [
                    "patientId": patient.id.uuidString,
                    "updatedFields": updates.keys.map { $0.rawValue }
                ]
            )
        } catch {
            await hipaaLogger.log(
                event: .patientUpdate,
                details: [
                    "action": "Patient Update Failed",
                    "patientId": patient.id.uuidString,
                    "error": error.localizedDescription,
                    "status": "failed"
                ]
            )
            
            throw errorHandler.handle(
                error,
                context: [
                    "action": "patientUpdate",
                    "patientId": patient.id.uuidString
                ]
            )
        }
    }
}

public enum PatientField: String {
    case firstName
    case lastName
    case dateOfBirth
    case gender
    case email
    case phone
    case address
    case medicalHistory
}

extension AnalyticsService.Event {
    static let patientRegistered = AnalyticsService.Event(name: "patient_registered")
    static let patientUpdated = AnalyticsService.Event(name: "patient_updated")
}

extension HIPAALogger.Event {
    static let patientRegistration = HIPAALogger.Event(name: "patient_registration")
    static let patientUpdate = HIPAALogger.Event(name: "patient_update")
}