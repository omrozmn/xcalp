import SwiftUI
import ComposableArchitecture
import Features

public enum DashboardDestination: NavigationDestination {
    case newScan
    case newPatient
    case treatment
    case analysis
    
    @ViewBuilder
    public var destination: some View {
        switch self {
        case .newScan:
            ScanningView(
                store: Store(
                    initialState: ScanningFeature.State(),
                    reducer: { ScanningFeature() }
                )
            )
        case .newPatient:
            PatientEditView(patient: nil)
        case .treatment:
            TreatmentPlanningView(
                store: Store(
                    initialState: TreatmentFeature.State(),
                    reducer: { TreatmentFeature() }
                )
            )
        case .analysis:
            AnalysisView(
                store: Store(
                    initialState: AnalysisFeature.State(),
                    reducer: { AnalysisFeature() }
                )
            )
        }
    }
}