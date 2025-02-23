import Foundation
import ComposableArchitecture

public struct PatientDetailFeature: Reducer {
    public struct State: Equatable {
        public var patient: Patient
        public var isLoading: Bool = false
        public var errorMessage: String?
        public var scans: [ScanData] = []
        public var treatments: [Treatment] = []
        public var isEditMode: Bool = false
        
        public init(patient: Patient) {
            self.patient = patient
        }
    }
    
    public enum Action: Equatable {
        case onAppear
        case loadPatientData
        case patientDataResponse(TaskResult<(scans: [ScanData], treatments: [Treatment])>)
        case editButtonTapped
        case deleteButtonTapped
        case deleteResponse(TaskResult<Bool>)
        case setError(String?)
    }
    
    @Dependency(\.continuousClock) var clock
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.loadPatientData)
                
            case .loadPatientData:
                state.isLoading = true
                state.errorMessage = nil
                
                return .run { [patientId = state.patient.id] send in
                    // Simulate network request
                    try await clock.sleep(for: .seconds(1))
                    
                    // TODO: Replace with actual data loading
                    let scans = [
                        ScanData(id: UUID(), date: Date(), quality: 0.95, notes: "Initial scan"),
                        ScanData(id: UUID(), date: Date().addingTimeInterval(-86400), quality: 0.88, notes: "Follow-up")
                    ]
                    
                    let treatments = [
                        Treatment(id: UUID(), date: Date(), type: .analysis, status: .completed),
                        Treatment(id: UUID(), date: Date().addingTimeInterval(-86400*2), type: .planning, status: .inProgress)
                    ]
                    
                    await send(.patientDataResponse(.success((scans: scans, treatments: treatments))))
                } catch: { error in
                    await send(.patientDataResponse(.failure(error)))
                }
                
            case let .patientDataResponse(.success(data)):
                state.isLoading = false
                state.scans = data.scans
                state.treatments = data.treatments
                return .none
                
            case let .patientDataResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none
                
            case .editButtonTapped:
                state.isEditMode = true
                return .none
                
            case .deleteButtonTapped:
                state.isLoading = true
                state.errorMessage = nil
                
                return .run { [patientId = state.patient.id] send in
                    // Simulate network request
                    try await clock.sleep(for: .seconds(1))
                    
                    // TODO: Replace with actual delete operation
                    await send(.deleteResponse(.success(true)))
                } catch: { error in
                    await send(.deleteResponse(.failure(error)))
                }
                
            case let .deleteResponse(.success(success)):
                state.isLoading = false
                return .none
                
            case let .deleteResponse(.failure(error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none
                
            case let .setError(message):
                state.errorMessage = message
                return .none
            }
        }
    }
}

// Models
public struct ScanData: Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let quality: Double
    public let notes: String
}

public struct Treatment: Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let type: TreatmentType
    public let status: TreatmentStatus
    
    public enum TreatmentType: String, Equatable {
        case analysis
        case planning
        case procedure
        case followUp = "followUp"
    }
    
    public enum TreatmentStatus: String, Equatable {
        case scheduled
        case inProgress = "inProgress"
        case completed
        case cancelled
    }
}
