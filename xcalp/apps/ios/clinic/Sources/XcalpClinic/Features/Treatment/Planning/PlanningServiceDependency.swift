import ComposableArchitecture
import Dependencies
import Foundation

private enum PlanningServiceKey: DependencyKey {
    static let liveValue: TreatmentPlanningService = TreatmentPlanningService()
    static let testValue: TreatmentPlanningService = TreatmentPlanningService()
}

extension DependencyValues {
    var planningService: TreatmentPlanningService {
        get { self[PlanningServiceKey.self] }
        set { self[PlanningServiceKey.self] = newValue }
    }
}
