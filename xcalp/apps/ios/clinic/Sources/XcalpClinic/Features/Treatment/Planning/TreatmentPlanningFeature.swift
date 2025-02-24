import ComposableArchitecture
import Foundation

@Reducer
struct TreatmentPlanningFeature {
    struct State: Equatable {
        var availableTemplates: [TreatmentTemplate] = []
        var selectedTemplate: TreatmentTemplate?
        var currentScan: ScanData?
        var generatedPlan: TreatmentPlan?
        var isGenerating = false
        var error: String?
    }
    
    enum Action {
        case loadTemplates
        case templatesLoaded([TreatmentTemplate])
        case selectTemplate(TreatmentTemplate?)
        case setScanData(ScanData?)
        case generatePlan
        case planGenerated(TreatmentPlan)
        case setError(String?)
    }
    
    @Dependency(\.templateManager) var templateManager
    @Dependency(\.planningService) var planningService
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTemplates:
                state.error = nil
                return .run { send in
                    let templates = templateManager.templates
                    await send(.templatesLoaded(templates))
                }
                
            case let .templatesLoaded(templates):
                state.availableTemplates = templates
                return .none
                
            case let .selectTemplate(template):
                state.selectedTemplate = template
                state.generatedPlan = nil
                return .none
                
            case let .setScanData(scan):
                state.currentScan = scan
                state.generatedPlan = nil
                return .none
                
            case .generatePlan:
                guard let template = state.selectedTemplate,
                      let scan = state.currentScan else {
                    return .run { send in
                        await send(.setError("Please select a template and scan first"))
                    }
                }
                
                state.isGenerating = true
                state.error = nil
                
                return .run { send in
                    do {
                        let plan = try planningService.applyTemplate(template, to: scan)
                        await send(.planGenerated(plan))
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }
                
            case let .planGenerated(plan):
                state.isGenerating = false
                state.generatedPlan = plan
                return .none
                
            case let .setError(error):
                state.error = error
                state.isGenerating = false
                return .none
            }
        }
    }
}
