import Foundation
import ComposableArchitecture

@Reducer
struct TreatmentTemplateFeature {
    struct State: Equatable {
        var templates: [TreatmentTemplate] = []
        var selectedTemplate: TreatmentTemplate?
        var isCreatingNew = false
        var error: String?
    }
    
    enum Action {
        case loadTemplates
        case templatesLoaded([TreatmentTemplate])
        case selectTemplate(TreatmentTemplate?)
        case createNewTemplate
        case saveTemplate(TreatmentTemplate)
        case templateSaved
        case deleteTemplate(TreatmentTemplate)
        case templateDeleted
        case updateTemplate(TreatmentTemplate)
        case templateUpdated
        case setError(String?)
    }
    
    @Dependency(\.templateManager) var templateManager
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTemplates:
                state.error = nil
                return .run { send in
                    let templates = templateManager.loadTemplates()
                    await send(.templatesLoaded(templates))
                }
                
            case let .templatesLoaded(templates):
                state.templates = templates
                return .none
                
            case let .selectTemplate(template):
                state.selectedTemplate = template
                state.isCreatingNew = false
                return .none
                
            case .createNewTemplate:
                state.selectedTemplate = nil
                state.isCreatingNew = true
                return .none
                
            case let .saveTemplate(template):
                return .run { send in
                    do {
                        try templateManager.saveTemplate(template)
                        await send(.templateSaved)
                        await send(.loadTemplates)
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }
                
            case .templateSaved:
                state.isCreatingNew = false
                return .none
                
            case let .deleteTemplate(template):
                return .run { send in
                    do {
                        try templateManager.deleteTemplate(template)
                        await send(.templateDeleted)
                        await send(.loadTemplates)
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }
                
            case .templateDeleted:
                state.selectedTemplate = nil
                return .none
                
            case let .updateTemplate(template):
                return .run { send in
                    do {
                        try templateManager.updateTemplate(template)
                        await send(.templateUpdated)
                        await send(.loadTemplates)
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }
                
            case .templateUpdated:
                return .none
                
            case let .setError(error):
                state.error = error
                return .none
            }
        }
    }
}