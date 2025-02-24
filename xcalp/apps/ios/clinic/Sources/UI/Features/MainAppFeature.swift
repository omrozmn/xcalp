import ComposableArchitecture
import Foundation

public struct MainAppFeature: Reducer {
    public struct State: Equatable {
        public var selectedTab: Tab
        public var scanning: ScanningFeature.State
        public var patients: PatientListFeature.State
        public var treatment: TreatmentFeature.State
        public var analysis: AnalysisFeature.State
        public var settings: SettingsFeature.State
        
        public init(
            selectedTab: Tab = .scanning,
            scanning: ScanningFeature.State = .init(),
            patients: PatientListFeature.State = .init(),
            treatment: TreatmentFeature.State = .init(),
            analysis: AnalysisFeature.State = .init(),
            settings: SettingsFeature.State = .init()
        ) {
            self.selectedTab = selectedTab
            self.scanning = scanning
            self.patients = patients
            self.treatment = treatment
            self.analysis = analysis
            self.settings = settings
        }
        
        public enum Tab: Equatable {
            case scanning
            case patients
            case treatment
            case analysis
            case settings
        }
    }
    
    public enum Action: Equatable {
        case tabSelected(State.Tab)
        case scanning(ScanningFeature.Action)
        case patients(PatientListFeature.Action)
        case treatment(TreatmentFeature.Action)
        case analysis(AnalysisFeature.Action)
        case settings(SettingsFeature.Action)
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
                
            case .scanning, .patients, .treatment, .analysis, .settings:
                return .none
            }
        }
        
        Scope(state: \.scanning, action: /Action.scanning) {
            ScanningFeature()
        }
        
        Scope(state: \.patients, action: /Action.patients) {
            PatientListFeature()
        }
        
        Scope(state: \.treatment, action: /Action.treatment) {
            TreatmentFeature()
        }
        
        Scope(state: \.analysis, action: /Action.analysis) {
            AnalysisFeature()
        }
        
        Scope(state: \.settings, action: /Action.settings) {
            SettingsFeature()
        }
    }
}
