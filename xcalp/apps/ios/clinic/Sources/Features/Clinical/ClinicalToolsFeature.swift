import CoreML
import Metal
import SwiftUI

public struct ClinicalToolsFeature: ReducerProtocol {
    public struct State: Equatable {
        var currentAnalysis: AnalysisType?
        var measurements: [Measurement] = []
        var analysisResults: AnalysisResults?
        var isProcessing: Bool = false
        var currentError: AnalysisError?
        var documentationStatus: DocumentationStatus = .notStarted
    }
    
    public enum Action: Equatable {
        case startAnalysis(AnalysisType)
        case measurementAdded(Measurement)
        case analysisCompleted(Result<AnalysisResults, AnalysisError>)
        case generateReport
        case reportGenerated(Result<URL, ReportError>)
        case clearAnalysis
    }
    
    public enum AnalysisType: Equatable {
        case densityMapping
        case growthProjection
        case graftPlacement
        case environmentalAnalysis
    }
    
    public enum AnalysisError: Error, Equatable {
        case insufficientData
        case processingFailed
        case invalidMeasurements
        case modelError
    }
    
    public enum DocumentationStatus: Equatable {
        case notStarted
        case inProgress
        case completed
        case error(String)
    }
    
    @Dependency(\.analysisEngine) var analysisEngine
    @Dependency(\.reportGenerator) var reportGenerator
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .startAnalysis(let type):
                state.currentAnalysis = type
                state.isProcessing = true
                return performAnalysis(type, measurements: state.measurements)
                
            case .measurementAdded(let measurement):
                state.measurements.append(measurement)
                return .none
                
            case .analysisCompleted(.success(let results)):
                state.analysisResults = results
                state.isProcessing = false
                return .none
                
            case .analysisCompleted(.failure(let error)):
                state.currentError = error
                state.isProcessing = false
                return .none
                
            case .generateReport:
                guard let results = state.analysisResults else { return .none }
                return generateClinicalReport(results)
                
            case .reportGenerated(.success):
                state.documentationStatus = .completed
                return .none
                
            case .reportGenerated(.failure):
                state.documentationStatus = .error("Failed to generate report")
                return .none
                
            case .clearAnalysis:
                state.currentAnalysis = nil
                state.measurements = []
                state.analysisResults = nil
                state.currentError = nil
                state.documentationStatus = .notStarted
                return .none
            }
        }
    }
    
    private func performAnalysis(_ type: AnalysisType, measurements: [Measurement]) -> Effect<Action, Never> {
        Effect.task {
            do {
                let results = try await analysisEngine.analyze(type: type, measurements: measurements)
                return .analysisCompleted(.success(results))
            } catch {
                return .analysisCompleted(.failure(.processingFailed))
            }
        }
    }
    
    private func generateClinicalReport(_ results: AnalysisResults) -> Effect<Action, Never> {
        Effect.task {
            do {
                let reportURL = try await reportGenerator.generate(from: results)
                return .reportGenerated(.success(reportURL))
            } catch {
                return .reportGenerated(.failure(.generationFailed))
            }
        }
    }
}
