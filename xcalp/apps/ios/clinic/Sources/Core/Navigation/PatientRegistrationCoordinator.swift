import SwiftUI
import ComposableArchitecture

public class PatientRegistrationCoordinator: ObservableObject {
    @Published public var path = NavigationPath()
    @Published public var activeSheet: RegistrationSheet?
    @Published public var alertItem: AlertItem?
    
    private let analytics: AnalyticsService
    private let errorHandler: ErrorHandler
    
    public init(
        analytics: AnalyticsService = .shared,
        errorHandler: ErrorHandler = .shared
    ) {
        self.analytics = analytics
        self.errorHandler = errorHandler
    }
    
    public func showRegistrationForm() {
        let store = Store(
            initialState: PatientRegistrationFeature.State(),
            reducer: { PatientRegistrationFeature() }
        )
        
        activeSheet = .registration(store)
        analytics.track(event: .registrationStarted)
    }
    
    public func handleRegistrationComplete(_ patient: Patient) {
        activeSheet = nil
        analytics.track(
            event: .registrationCompleted,
            properties: ["patientId": patient.id.uuidString]
        )
        
        alertItem = AlertItem(
            title: "Success",
            message: "Patient registration completed successfully",
            primaryButton: .default("OK") {
                self.path.append(PatientDetailDestination.detail(patient))
            }
        )
    }
    
    public func handleRegistrationError(_ error: Error) {
        errorHandler.handleError(error)
        analytics.track(
            event: .registrationFailed,
            properties: ["error": error.localizedDescription]
        )
        
        alertItem = AlertItem(
            title: "Registration Failed",
            message: error.localizedDescription,
            primaryButton: .default("OK")
        )
    }
}

extension PatientRegistrationCoordinator {
    public enum RegistrationSheet: Identifiable {
        case registration(StoreOf<PatientRegistrationFeature>)
        
        public var id: String {
            switch self {
            case .registration:
                return "registration"
            }
        }
    }
}

extension AnalyticsService.Event {
    static let registrationStarted = AnalyticsService.Event(name: "registration_started")
    static let registrationCompleted = AnalyticsService.Event(name: "registration_completed")
    static let registrationFailed = AnalyticsService.Event(name: "registration_failed")
}

public struct AlertItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let primaryButton: Alert.Button
    public var secondaryButton: Alert.Button?
}

public enum PatientDetailDestination {
    case detail(Patient)
}