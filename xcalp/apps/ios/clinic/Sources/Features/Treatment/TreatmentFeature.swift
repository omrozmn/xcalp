import Foundation
import SwiftUI
import CoreML
import Combine

public struct TreatmentFeature: ReducerProtocol {
    public struct State: Equatable {
        var currentPlan: TreatmentPlan?
        var selectedTemplate: TreatmentTemplate?
        var planningStage: PlanningStage = .initial
        var measurements: [TreatmentMeasurement] = []
        var calculations: TreatmentCalculations?
        var validationResults: ValidationResults?
        var currentError: TreatmentError?
        var progress: Double = 0.0
    }
    
    public enum Action: Equatable {
        case loadTemplate(String)
        case templateLoaded(Result<TreatmentTemplate, TreatmentError>)
        case startPlanning(TreatmentTemplate)
        case addMeasurement(TreatmentMeasurement)
        case calculatePlan
        case planCalculated(Result<TreatmentCalculations, TreatmentError>)
        case validatePlan
        case planValidated(Result<ValidationResults, TreatmentError>)
        case savePlan
        case planSaved(Result<TreatmentPlan, TreatmentError>)
        case updateProgress(Double)
    }
    
    public enum PlanningStage: Equatable {
        case initial
        case templateSelection
        case measurement
        case calculation
        case validation
        case finalization
        case completed
        case error(String)
    }
    
    public struct TreatmentPlan: Identifiable, Equatable {
        public let id: String
        var templateId: String
        var measurements: [TreatmentMeasurement]
        var calculations: TreatmentCalculations
        var validationResults: ValidationResults
        var status: PlanStatus
        var createdAt: Date
        var updatedAt: Date
    }
    
    public enum PlanStatus: String, Equatable {
        case draft = "draft"
        case inProgress = "in_progress"
        case completed = "completed"
        case cancelled = "cancelled"
    }
    
    public enum TreatmentError: Error, Equatable {
        case templateNotFound
        case invalidMeasurements
        case calculationFailed
        case validationFailed
        case saveFailed
        case insufficientData
    }
    
    @Dependency(\.treatmentPlanner) var treatmentPlanner
    @Dependency(\.templateManager) var templateManager
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadTemplate(let id):
                return loadTreatmentTemplate(id)
                
            case .templateLoaded(.success(let template)):
                state.selectedTemplate = template
                state.planningStage = .templateSelection
                return .none
                
            case .templateLoaded(.failure(let error)):
                state.currentError = error
                state.planningStage = .error(error.localizedDescription)
                return .none
                
            case .startPlanning(let template):
                state.selectedTemplate = template
                state.planningStage = .measurement
                return .none
                
            case .addMeasurement(let measurement):
                state.measurements.append(measurement)
                return .none
                
            case .calculatePlan:
                guard !state.measurements.isEmpty else {
                    state.currentError = .insufficientData
                    return .none
                }
                state.planningStage = .calculation
                return calculateTreatmentPlan(measurements: state.measurements)
                
            case .planCalculated(.success(let calculations)):
                state.calculations = calculations
                state.planningStage = .validation
                return .send(.validatePlan)
                
            case .planCalculated(.failure(let error)):
                state.currentError = error
                state.planningStage = .error(error.localizedDescription)
                return .none
                
            case .validatePlan:
                guard let calculations = state.calculations else { return .none }
                return validateTreatmentPlan(calculations)
                
            case .planValidated(.success(let results)):
                state.validationResults = results
                state.planningStage = .finalization
                return .none
                
            case .planValidated(.failure(let error)):
                state.currentError = error
                state.planningStage = .error(error.localizedDescription)
                return .none
                
            case .savePlan:
                return saveTreatmentPlan(
                    template: state.selectedTemplate,
                    measurements: state.measurements,
                    calculations: state.calculations,
                    validation: state.validationResults
                )
                
            case .planSaved(.success(let plan)):
                state.currentPlan = plan
                state.planningStage = .completed
                return .none
                
            case .planSaved(.failure(let error)):
                state.currentError = error
                state.planningStage = .error(error.localizedDescription)
                return .none
                
            case .updateProgress(let progress):
                state.progress = progress
                return .none
            }
        }
    }
    
    private func loadTreatmentTemplate(_ id: String) -> Effect<Action, Never> {
        Effect.task {
            do {
                let template = try await templateManager.loadTemplate(id)
                return .templateLoaded(.success(template))
            } catch {
                return .templateLoaded(.failure(.templateNotFound))
            }
        }
    }
    
    private func calculateTreatmentPlan(measurements: [TreatmentMeasurement]) -> Effect<Action, Never> {
        Effect.task {
            do {
                let calculations = try await treatmentPlanner.calculate(measurements)
                return .planCalculated(.success(calculations))
            } catch {
                return .planCalculated(.failure(.calculationFailed))
            }
        }
    }
    
    private func validateTreatmentPlan(_ calculations: TreatmentCalculations) -> Effect<Action, Never> {
        Effect.task {
            do {
                let results = try await treatmentPlanner.validate(calculations)
                return .planValidated(.success(results))
            } catch {
                return .planValidated(.failure(.validationFailed))
            }
        }
    }
    
    private func saveTreatmentPlan(
        template: TreatmentTemplate?,
        measurements: [TreatmentMeasurement],
        calculations: TreatmentCalculations?,
        validation: ValidationResults?
    ) -> Effect<Action, Never> {
        Effect.task {
            do {
                guard let template = template,
                      let calculations = calculations,
                      let validation = validation else {
                    return .planSaved(.failure(.insufficientData))
                }
                
                let plan = try await treatmentPlanner.savePlan(
                    templateId: template.id,
                    measurements: measurements,
                    calculations: calculations,
                    validation: validation
                )
                return .planSaved(.success(plan))
            } catch {
                return .planSaved(.failure(.saveFailed))
            }
        }
    }
}

public struct TreatmentSimulationFeature: ReducerProtocol {
    public struct State: Equatable {
        var selectedTemplate: TreatmentTemplate?
        var patientData: PatientData?
        var simulationStatus: SimulationStatus = .idle
        var currentResults: TreatmentTemplate.SimulationResults?
        var timelineProgress: Double = 0.0
        var monthlyUpdates: [MonthlyUpdate] = []
        
        struct MonthlyUpdate: Identifiable, Equatable {
            let id: UUID
            let month: Int
            let expectedDensity: Double
            let growthRate: Double
            let notes: String
        }
    }
    
    public enum Action: Equatable {
        case selectTemplate(TreatmentTemplate)
        case updatePatientData(PatientData)
        case runSimulation
        case simulationCompleted(TreatmentTemplate.SimulationResults)
        case updateTimelineProgress(Double)
        case generateMonthlyUpdate
        case resetSimulation
    }
    
    public enum SimulationStatus: Equatable {
        case idle
        case running
        case completed
        case error(String)
    }
    
    @Dependency(\.simulationEngine) var simulationEngine
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .selectTemplate(let template):
                state.selectedTemplate = template
                return .none
                
            case .updatePatientData(let data):
                state.patientData = data
                return .none
                
            case .runSimulation:
                guard let template = state.selectedTemplate,
                      let patientData = state.patientData else {
                    return .none
                }
                
                state.simulationStatus = .running
                
                return Effect.task {
                    do {
                        var updatedTemplate = template
                        let results = updatedTemplate.simulate(patientData: patientData)
                        return .simulationCompleted(results)
                    } catch {
                        state.simulationStatus = .error("Simulation failed: \(error.localizedDescription)")
                        return .resetSimulation
                    }
                }
                
            case .simulationCompleted(let results):
                state.simulationStatus = .completed
                state.currentResults = results
                return Effect.merge(
                    Effect(value: .updateTimelineProgress(0)),
                    Effect(value: .generateMonthlyUpdate)
                )
                
            case .updateTimelineProgress(let progress):
                state.timelineProgress = progress
                if progress >= 1.0 {
                    return .none
                }
                return Effect(value: .updateTimelineProgress(progress + 0.01))
                    .delay(for: .milliseconds(50), scheduler: DispatchQueue.main)
                    .eraseToEffect()
                
            case .generateMonthlyUpdate:
                guard let results = state.currentResults else { return .none }
                
                let currentMonth = Int(state.timelineProgress * 12)
                if currentMonth > state.monthlyUpdates.count {
                    let update = MonthlyUpdate(
                        id: UUID(),
                        month: currentMonth,
                        expectedDensity: results.coverageEstimate * Double(currentMonth) / 12.0,
                        growthRate: results.expectedGrowthRate,
                        notes: generateMonthlyNotes(month: currentMonth, results: results)
                    )
                    state.monthlyUpdates.append(update)
                }
                return .none
                
            case .resetSimulation:
                state.simulationStatus = .idle
                state.currentResults = nil
                state.timelineProgress = 0
                state.monthlyUpdates = []
                return .none
            }
        }
    }
    
    private func generateMonthlyNotes(month: Int, results: TreatmentTemplate.SimulationResults) -> String {
        if let marker = results.timelineMarkers.first(where: { $0.month == month }) {
            return marker.description
        }
        
        // Generate intermediate notes
        switch month {
        case 0...1:
            return "Initial healing phase in progress"
        case 2...3:
            return "Early signs of growth expected"
        case 4...6:
            return "Continued growth and density improvement"
        case 7...9:
            return "Significant progress in coverage"
        case 10...12:
            return "Final results becoming visible"
        default:
            return "Maintenance phase"
        }
    }
}