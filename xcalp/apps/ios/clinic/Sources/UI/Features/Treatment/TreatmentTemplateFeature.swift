import ComposableArchitecture
import Foundation

@Reducer
struct TreatmentTemplateFeature {
    struct State: Equatable {
        var templates: IdentifiedArrayOf<TreatmentTemplate> = []
        var selectedTemplate: TreatmentTemplate?
        var isEditing: Bool = false
        var isSaving: Bool = false
        var showingParameterCreator = false
        var showingRegionCreator = false
        var showingVersionHistory = false
        var templateVersions: [TreatmentTemplate] = []
        var error: String?
    }
    
    enum Action {
        case loadTemplates
        case templatesResponse(TaskResult<[TreatmentTemplate]>)
        case selectTemplate(TreatmentTemplate)
        case createTemplate
        case editTemplate(TreatmentTemplate)
        case updateName(String)
        case updateDescription(String)
        case updateParameter(TreatmentTemplate.Parameter)
        case deleteParameter(TreatmentTemplate.Parameter)
        case updateRegion(TreatmentRegion)
        case deleteRegion(TreatmentRegion)
        case showParameterCreator
        case hideParameterCreator
        case addParameter(TreatmentTemplate.Parameter)
        case showRegionCreator
        case hideRegionCreator
        case addRegion(TreatmentRegion)
        case saveTemplate
        case saveTemplateResponse(TaskResult<TreatmentTemplate>)
        case deleteTemplate(TreatmentTemplate)
        case deleteTemplateResponse(TaskResult<Bool>)
        case dismissError
        case loadVersionHistory(UUID)
        case versionsLoaded(TaskResult<[TreatmentTemplate]>)
        case restoreVersion(TreatmentTemplate)
        case versionRestored(TaskResult<TreatmentTemplate>)
    }
    
    @Dependency(\.templateClient) var templateClient
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadTemplates:
                return .run { send in
                    await send(.templatesResponse(TaskResult {
                        try await templateClient.loadTemplates()
                    }))
                }
                
            case let .templatesResponse(.success(templates)):
                state.templates = IdentifiedArray(uniqueElements: templates)
                return .none
                
            case let .templatesResponse(.failure(error)):
                state.error = error.localizedDescription
                return .none
                
            case let .selectTemplate(template):
                state.selectedTemplate = template
                state.isEditing = false
                return .none
                
            case .createTemplate:
                let newTemplate = TreatmentTemplate(
                    id: UUID(),
                    name: "New Template",
                    description: "",
                    version: 1,
                    createdAt: Date(),
                    updatedAt: Date(),
                    parameters: [],
                    regions: [],
                    author: "", // TODO: Get from auth
                    isCustom: true,
                    parentTemplateId: nil
                )
                state.selectedTemplate = newTemplate
                state.isEditing = true
                return .none
                
            case let .editTemplate(template):
                state.selectedTemplate = template
                state.isEditing = true
                return .none
                
            case let .updateName(name):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: name,
                    description: template.description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters,
                    regions: template.regions,
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                return .none
                
            case let .updateDescription(description):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: template.name,
                    description: description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters,
                    regions: template.regions,
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                return .none
                
            case let .updateParameter(parameter):
                guard var template = state.selectedTemplate else { return .none }
                if let index = template.parameters.firstIndex(where: { $0.id == parameter.id }) {
                    var parameters = template.parameters
                    parameters[index] = parameter
                    template = TreatmentTemplate(
                        id: template.id,
                        name: template.name,
                        description: template.description,
                        version: template.version,
                        createdAt: template.createdAt,
                        updatedAt: Date(),
                        parameters: parameters,
                        regions: template.regions,
                        author: template.author,
                        isCustom: template.isCustom,
                        parentTemplateId: template.parentTemplateId
                    )
                    state.selectedTemplate = template
                }
                return .none
                
            case let .deleteParameter(parameter):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: template.name,
                    description: template.description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters.filter { $0.id != parameter.id },
                    regions: template.regions,
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                return .none
                
            case let .updateRegion(region):
                guard var template = state.selectedTemplate else { return .none }
                if let index = template.regions.firstIndex(where: { $0.id == region.id }) {
                    var regions = template.regions
                    regions[index] = region
                    template = TreatmentTemplate(
                        id: template.id,
                        name: template.name,
                        description: template.description,
                        version: template.version,
                        createdAt: template.createdAt,
                        updatedAt: Date(),
                        parameters: template.parameters,
                        regions: regions,
                        author: template.author,
                        isCustom: template.isCustom,
                        parentTemplateId: template.parentTemplateId
                    )
                    state.selectedTemplate = template
                }
                return .none
                
            case let .deleteRegion(region):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: template.name,
                    description: template.description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters,
                    regions: template.regions.filter { $0.id != region.id },
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                return .none
                
            case .showParameterCreator:
                state.showingParameterCreator = true
                return .none
                
            case .hideParameterCreator:
                state.showingParameterCreator = false
                return .none
                
            case let .addParameter(parameter):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: template.name,
                    description: template.description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters + [parameter],
                    regions: template.regions,
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                state.showingParameterCreator = false
                return .none
                
            case .showRegionCreator:
                state.showingRegionCreator = true
                return .none
                
            case .hideRegionCreator:
                state.showingRegionCreator = false
                return .none
                
            case let .addRegion(region):
                guard var template = state.selectedTemplate else { return .none }
                template = TreatmentTemplate(
                    id: template.id,
                    name: template.name,
                    description: template.description,
                    version: template.version,
                    createdAt: template.createdAt,
                    updatedAt: Date(),
                    parameters: template.parameters,
                    regions: template.regions + [region],
                    author: template.author,
                    isCustom: template.isCustom,
                    parentTemplateId: template.parentTemplateId
                )
                state.selectedTemplate = template
                state.showingRegionCreator = false
                return .none
                
            case .saveTemplate:
                guard let template = state.selectedTemplate else { return .none }
                guard template.isValid else {
                    state.error = "Please fix validation errors before saving"
                    return .none
                }
                state.isSaving = true
                return .run { send in
                    await send(.saveTemplateResponse(TaskResult {
                        try await templateClient.saveTemplate(template)
                    }))
                }
                
            case let .saveTemplateResponse(.success(template)):
                state.isSaving = false
                if let index = state.templates.firstIndex(where: { $0.id == template.id }) {
                    state.templates[index] = template
                } else {
                    state.templates.append(template)
                }
                state.selectedTemplate = nil
                state.isEditing = false
                return .none
                
            case let .saveTemplateResponse(.failure(error)):
                state.isSaving = false
                state.error = error.localizedDescription
                return .none
                
            case let .deleteTemplate(template):
                return .run { send in
                    await send(.deleteTemplateResponse(TaskResult {
                        try await templateClient.deleteTemplate(template.id)
                    }))
                }
                
            case .deleteTemplateResponse(.success):
                if let template = state.selectedTemplate {
                    state.templates.remove(id: template.id)
                    state.selectedTemplate = nil
                    state.isEditing = false
                }
                return .none
                
            case let .deleteTemplateResponse(.failure(error)):
                state.error = error.localizedDescription
                return .none
                
            case .dismissError:
                state.error = nil
                return .none
                
            case let .loadVersionHistory(templateId):
                state.showingVersionHistory = true
                return .run { send in
                    await send(.versionsLoaded(TaskResult {
                        try await templateClient.loadVersionHistory(templateId)
                    }))
                }
                
            case let .versionsLoaded(.success(versions)):
                state.templateVersions = versions
                return .none
                
            case let .versionsLoaded(.failure(error)):
                state.error = error.localizedDescription
                state.showingVersionHistory = false
                return .none
                
            case let .restoreVersion(template):
                state.isSaving = true
                return .run { send in
                    await send(.versionRestored(TaskResult {
                        try await templateClient.restoreVersion(template)
                    }))
                }
                
            case let .versionRestored(.success(template)):
                state.isSaving = false
                if let index = state.templates.firstIndex(where: { $0.id == template.id }) {
                    state.templates[index] = template
                }
                state.selectedTemplate = template
                state.showingVersionHistory = false
                return .none
                
            case let .versionRestored(.failure(error)):
                state.isSaving = false
                state.error = error.localizedDescription
                return .none
            }
        }
    }
}