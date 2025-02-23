import ComposableArchitecture
import Foundation

@Reducer
struct TreatmentFeature {
    struct State: Equatable {
        var templateFeature = TreatmentTemplateFeature.State()
        var selectedPatientId: UUID?
        var currentTreatment: Treatment?
        var isApplyingTemplate: Bool = false
        var error: String?
        
        struct Treatment: Equatable {
            var patientId: UUID
            var appliedTemplate: TreatmentTemplate?
            var regions: [TreatmentRegion]
            var notes: String
            var createdAt: Date
            var updatedAt: Date
        }
    }
    
    enum Action {
        case templateFeature(TreatmentTemplateFeature.Action)
        case selectPatient(UUID)
        case loadTreatment
        case treatmentResponse(TaskResult<State.Treatment?>)
        case applyTemplate(TreatmentTemplate)
        case updateRegions([TreatmentRegion])
        case updateNotes(String)
        case saveTreatment
        case saveTreatmentResponse(TaskResult<State.Treatment>)
        case dismissError
    }
    
    var body: some ReducerOf<Self> {
        Scope(state: \.templateFeature, action: /Action.templateFeature) {
            TreatmentTemplateFeature()
        }
        
        Reduce { state, action in
            switch action {
            case let .selectPatient(patientId):
                state.selectedPatientId = patientId
                return .send(.loadTreatment)
                
            case .loadTreatment:
                guard let patientId = state.selectedPatientId else { return .none }
                return .run { send in
                    await send(.treatmentResponse(TaskResult {
                        try await loadTreatmentForPatient(patientId)
                    }))
                }
                
            case let .treatmentResponse(.success(treatment)):
                state.currentTreatment = treatment
                return .none
                
            case let .treatmentResponse(.failure(error)):
                state.error = error.localizedDescription
                return .none
                
            case let .applyTemplate(template):
                guard var treatment = state.currentTreatment else {
                    guard let patientId = state.selectedPatientId else { return .none }
                    state.currentTreatment = State.Treatment(
                        patientId: patientId,
                        appliedTemplate: template,
                        regions: template.regions,
                        notes: "",
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    return .none
                }
                
                treatment.appliedTemplate = template
                treatment.regions = template.regions
                treatment.updatedAt = Date()
                state.currentTreatment = treatment
                return .none
                
            case let .updateRegions(regions):
                guard var treatment = state.currentTreatment else { return .none }
                treatment.regions = regions
                treatment.updatedAt = Date()
                state.currentTreatment = treatment
                return .none
                
            case let .updateNotes(notes):
                guard var treatment = state.currentTreatment else { return .none }
                treatment.notes = notes
                treatment.updatedAt = Date()
                state.currentTreatment = treatment
                return .none
                
            case .saveTreatment:
                guard let treatment = state.currentTreatment else { return .none }
                return .run { send in
                    await send(.saveTreatmentResponse(TaskResult {
                        try await saveTreatment(treatment)
                    }))
                }
                
            case let .saveTreatmentResponse(.success(treatment)):
                state.currentTreatment = treatment
                return .none
                
            case let .saveTreatmentResponse(.failure(error)):
                state.error = error.localizedDescription
                return .none
                
            case .dismissError:
                state.error = nil
                return .none
                
            case .templateFeature:
                return .none
            }
        }
    }
    
    private func loadTreatmentForPatient(_ patientId: UUID) async throws -> State.Treatment? {
        // TODO: Implement actual loading from storage
        return nil
    }
    
    private func saveTreatment(_ treatment: State.Treatment) async throws -> State.Treatment {
        // TODO: Implement actual saving to storage
        return treatment
    }
}