import Foundation
import SwiftUI

public struct TemplateFeature: ReducerProtocol {
    public struct State: Equatable {
        var templates: [TreatmentTemplate] = []
        var currentTemplate: TreatmentTemplate?
        var isEditing: Bool = false
        var parameters: [TemplateParameter] = []
        var versionHistory: [TemplateVersion] = []
        var currentError: TemplateError?
    }
    
    public enum Action: Equatable {
        case loadTemplates
        case templatesLoaded(Result<[TreatmentTemplate], TemplateError>)
        case createTemplate(TreatmentTemplate)
        case updateTemplate(TreatmentTemplate)
        case deleteTemplate(String)
        case saveVersion(String)
        case templateSaved(Result<TreatmentTemplate, TemplateError>)
        case setParameters([TemplateParameter])
        case loadVersionHistory(String)
        case versionsLoaded(Result<[TemplateVersion], TemplateError>)
    }
    
    public struct TreatmentTemplate: Identifiable, Equatable {
        public let id: String
        var name: String
        var description: String
        var parameters: [TemplateParameter]
        var defaultValues: [String: Any]
        var version: Int
        var createdAt: Date
        var updatedAt: Date
    }
    
    public struct TemplateParameter: Identifiable, Equatable {
        public let id: String
        var name: String
        var type: ParameterType
        var defaultValue: Any
        var range: ParameterRange?
        var required: Bool
        
        public static func == (lhs: TemplateParameter, rhs: TemplateParameter) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    public enum ParameterType: String, Equatable {
        case number
        case text
        case boolean
        case selection
        case range
    }
    
    public struct ParameterRange: Equatable {
        var min: Double
        var max: Double
        var step: Double
    }
    
    public struct TemplateVersion: Identifiable, Equatable {
        public let id: String
        var templateId: String
        var version: Int
        var changes: [String]
        var createdAt: Date
        var createdBy: String
    }
    
    public enum TemplateError: Error, Equatable {
        case loadFailed
        case saveFailed
        case invalidParameters
        case versionExists
        case notFound
    }
    
    @Dependency(\.templateManager) var templateManager
    @Dependency(\.versionControl) var versionControl
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadTemplates:
                return loadAllTemplates()
                
            case .templatesLoaded(.success(let templates)):
                state.templates = templates
                return .none
                
            case .templatesLoaded(.failure(let error)):
                state.currentError = error
                return .none
                
            case .createTemplate(let template):
                return createNewTemplate(template)
                
            case .updateTemplate(let template):
                return updateExistingTemplate(template)
                
            case .deleteTemplate(let id):
                return deleteExistingTemplate(id)
                
            case .saveVersion(let templateId):
                return saveTemplateVersion(templateId)
                
            case .templateSaved(.success(let template)):
                if let index = state.templates.firstIndex(where: { $0.id == template.id }) {
                    state.templates[index] = template
                } else {
                    state.templates.append(template)
                }
                return .none
                
            case .templateSaved(.failure(let error)):
                state.currentError = error
                return .none
                
            case .setParameters(let parameters):
                state.parameters = parameters
                return .none
                
            case .loadVersionHistory(let templateId):
                return loadTemplateVersions(templateId)
                
            case .versionsLoaded(.success(let versions)):
                state.versionHistory = versions
                return .none
                
            case .versionsLoaded(.failure(let error)):
                state.currentError = error
                return .none
            }
        }
    }
    
    private func loadAllTemplates() -> Effect<Action, Never> {
        Effect.task {
            do {
                let templates = try await templateManager.loadTemplates()
                return .templatesLoaded(.success(templates))
            } catch {
                return .templatesLoaded(.failure(.loadFailed))
            }
        }
    }
    
    private func createNewTemplate(_ template: TreatmentTemplate) -> Effect<Action, Never> {
        Effect.task {
            do {
                let savedTemplate = try await templateManager.createTemplate(template)
                return .templateSaved(.success(savedTemplate))
            } catch {
                return .templateSaved(.failure(.saveFailed))
            }
        }
    }
    
    private func updateExistingTemplate(_ template: TreatmentTemplate) -> Effect<Action, Never> {
        Effect.task {
            do {
                let updatedTemplate = try await templateManager.updateTemplate(template)
                return .templateSaved(.success(updatedTemplate))
            } catch {
                return .templateSaved(.failure(.saveFailed))
            }
        }
    }
    
    private func deleteExistingTemplate(_ id: String) -> Effect<Action, Never> {
        Effect.task {
            do {
                try await templateManager.deleteTemplate(id)
                return .loadTemplates
            } catch {
                return .templatesLoaded(.failure(.notFound))
            }
        }
    }
    
    private func saveTemplateVersion(_ templateId: String) -> Effect<Action, Never> {
        Effect.task {
            do {
                let version = try await versionControl.saveVersion(templateId)
                return .loadVersionHistory(templateId)
            } catch {
                return .versionsLoaded(.failure(.saveFailed))
            }
        }
    }
    
    private func loadTemplateVersions(_ templateId: String) -> Effect<Action, Never> {
        Effect.task {
            do {
                let versions = try await versionControl.getVersionHistory(templateId)
                return .versionsLoaded(.success(versions))
            } catch {
                return .versionsLoaded(.failure(.loadFailed))
            }
        }
    }
}
