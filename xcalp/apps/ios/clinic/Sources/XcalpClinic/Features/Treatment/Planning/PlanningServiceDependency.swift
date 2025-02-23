import Foundation
import ComposableArchitecture
import Dependencies

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