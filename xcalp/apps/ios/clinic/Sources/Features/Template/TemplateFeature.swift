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
        var validationStatus: ValidationStatus = .pending
        var recommendations: [TemplateRecommendation] = []
        var optimizationStatus: OptimizationStatus = .notStarted
        var templateAnalytics: TemplateAnalytics?
        var processingMetrics: ProcessingMetrics?
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
        case validateTemplate(TreatmentTemplate)
        case validationCompleted(Result<ValidationStatus, TemplateError>)
        case optimizeTemplate(TreatmentTemplate)
        case optimizationCompleted(Result<OptimizationResults, TemplateError>)
        case generateRecommendations(TreatmentTemplate)
        case recommendationsGenerated(Result<[TemplateRecommendation], TemplateError>)
        case updateAnalytics(TemplateAnalytics)
        case updateProcessingMetrics(ProcessingMetrics)
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
    
    public struct TemplateAnalytics: Equatable {
        var successRate: Double
        var averageOutcome: Double
        var usageCount: Int
        var patientSatisfaction: Double
        var completionTime: TimeInterval
    }
    
    public struct ProcessingMetrics: Equatable {
        var processingTime: TimeInterval
        var memoryUsage: UInt64
        var optimizationLevel: OptimizationLevel
        var validationScore: Double
    }
    
    public struct TemplateRecommendation: Equatable {
        let id: String
        var parameter: String
        var suggestedValue: Any
        var confidence: Double
        var reasoning: String
        
        public static func == (lhs: TemplateRecommendation, rhs: TemplateRecommendation) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    public enum ValidationStatus: Equatable {
        case pending
        case inProgress
        case valid(Double)
        case invalid([ValidationError])
    }
    
    public enum OptimizationStatus: Equatable {
        case notStarted
        case optimizing(Double)
        case completed(OptimizationResults)
        case failed(String)
    }
    
    public struct OptimizationResults: Equatable {
        var improvedParameters: [TemplateParameter]
        var expectedOutcomeImprovement: Double
        var confidenceScore: Double
    }
    
    public enum ValidationError: Equatable {
        case invalidRange(String)
        case missingRequired(String)
        case incompatibleValues(String, String)
        case outOfBounds(String)
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
                
            case .validateTemplate(let template):
                state.validationStatus = .inProgress
                return validateTemplate(template)
                
            case .validationCompleted(.success(let status)):
                state.validationStatus = status
                return .none
                
            case .validationCompleted(.failure(let error)):
                state.currentError = error
                return .none
                
            case .optimizeTemplate(let template):
                state.optimizationStatus = .optimizing(0)
                return optimizeTemplate(template)
                
            case .optimizationCompleted(.success(let results)):
                state.optimizationStatus = .completed(results)
                return generateRecommendations(results)
                
            case .optimizationCompleted(.failure(let error)):
                state.optimizationStatus = .failed(error.localizedDescription)
                return .none
                
            case .generateRecommendations(let template):
                return generateTemplateRecommendations(template)
                
            case .recommendationsGenerated(.success(let recommendations)):
                state.recommendations = recommendations
                return .none
                
            case .recommendationsGenerated(.failure(let error)):
                state.currentError = error
                return .none
                
            case .updateAnalytics(let analytics):
                state.templateAnalytics = analytics
                return .none
                
            case .updateProcessingMetrics(let metrics):
                state.processingMetrics = metrics
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
    
    private func validateTemplate(_ template: TreatmentTemplate) -> Effect<Action, Never> {
        Effect.task {
            let startTime = Date()
            do {
                var errors: [ValidationError] = []
                
                // Validate required parameters
                for parameter in template.parameters where parameter.required {
                    if template.defaultValues[parameter.id] == nil {
                        errors.append(.missingRequired(parameter.name))
                    }
                }
                
                // Validate parameter ranges
                for parameter in template.parameters {
                    if let range = parameter.range,
                       let value = template.defaultValues[parameter.id] as? Double {
                        if value < range.min || value > range.max {
                            errors.append(.outOfBounds(parameter.name))
                        }
                    }
                }
                
                // Validate parameter compatibility
                if let incompatibilities = try await templateManager.validateParameterCompatibility(template) {
                    errors.append(contentsOf: incompatibilities)
                }
                
                let status: ValidationStatus = errors.isEmpty ? 
                    .valid(1.0) : .invalid(errors)
                
                let endTime = Date()
                let metrics = ProcessingMetrics(
                    processingTime: endTime.timeIntervalSince(startTime),
                    memoryUsage: getMemoryUsage(),
                    optimizationLevel: .high,
                    validationScore: errors.isEmpty ? 1.0 : 0.0
                )
                
                await send(.updateProcessingMetrics(metrics)).finish()
                
                return .validationCompleted(.success(status))
            } catch {
                return .validationCompleted(.failure(.invalidParameters))
            }
        }
    }
    
    private func optimizeTemplate(_ template: TreatmentTemplate) -> Effect<Action, Never> {
        Effect.task {
            do {
                let startTime = Date()
                
                // Perform ML-based optimization
                let optimizedTemplate = try await templateManager.optimizeTemplate(
                    template,
                    optimizationLevel: .high
                )
                
                let improvedParameters = optimizedTemplate.parameters
                let expectedImprovement = try await templateManager.calculateExpectedImprovement(
                    original: template,
                    optimized: optimizedTemplate
                )
                
                let results = OptimizationResults(
                    improvedParameters: improvedParameters,
                    expectedOutcomeImprovement: expectedImprovement,
                    confidenceScore: 0.95
                )
                
                let endTime = Date()
                let metrics = ProcessingMetrics(
                    processingTime: endTime.timeIntervalSince(startTime),
                    memoryUsage: getMemoryUsage(),
                    optimizationLevel: .high,
                    validationScore: 1.0
                )
                
                await send(.updateProcessingMetrics(metrics)).finish()
                
                return .optimizationCompleted(.success(results))
            } catch {
                return .optimizationCompleted(.failure(.saveFailed))
            }
        }
    }
    
    private func generateTemplateRecommendations(_ template: TreatmentTemplate) -> Effect<Action, Never> {
        Effect.task {
            do {
                let recommendations = try await templateManager.generateRecommendations(template)
                return .recommendationsGenerated(.success(recommendations))
            } catch {
                return .recommendationsGenerated(.failure(.loadFailed))
            }
        }
    }
    
    private func generateRecommendations(_ results: OptimizationResults) -> Effect<Action, Never> {
        Effect.task {
            do {
                var recommendations: [TemplateRecommendation] = []
                
                for parameter in results.improvedParameters {
                    let recommendation = TemplateRecommendation(
                        id: UUID().uuidString,
                        parameter: parameter.name,
                        suggestedValue: parameter.defaultValue,
                        confidence: results.confidenceScore,
                        reasoning: "Based on ML analysis and historical outcomes"
                    )
                    recommendations.append(recommendation)
                }
                
                return .recommendationsGenerated(.success(recommendations))
            } catch {
                return .recommendationsGenerated(.failure(.loadFailed))
            }
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
}
