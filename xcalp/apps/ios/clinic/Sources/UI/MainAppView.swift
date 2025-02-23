import SwiftUI
import ComposableArchitecture

public struct MainAppView: View {
    let store: Store<MainAppFeature.State?, MainAppFeature.Action>
    
    public init(store: Store<MainAppFeature.State?, MainAppFeature.Action>) {
        self.store = store
    }
    
    public var body: some View {
        IfLetStore(store) { store in
            WithViewStore(store, observe: { $0 }) { viewStore in
                TabView(selection: viewStore.binding(
                    get: \.selectedTab,
                    send: MainAppFeature.Action.tabSelected
                )) {
                    ScanningView(
                        store: store.scope(
                            state: \.scanning,
                            action: MainAppFeature.Action.scanning
                        )
                    )
                    .tabItem {
                        Label("Scanning", systemImage: "camera.viewfinder")
                    }
                    .tag(MainAppFeature.State.Tab.scanning)
                    
                    PatientListView(
                        store: store.scope(
                            state: \.patients,
                            action: MainAppFeature.Action.patients
                        )
                    )
                    .tabItem {
                        Label("Patients", systemImage: "person.2")
                    }
                    .tag(MainAppFeature.State.Tab.patients)
                    
                    AnalysisView(
                        store: store.scope(
                            state: \.analysis,
                            action: MainAppFeature.Action.analysis
                        )
                    )
                    .tabItem {
                        Label("Analysis", systemImage: "chart.bar")
                    }
                    .tag(MainAppFeature.State.Tab.analysis)
                    
                    SettingsView(
                        store: store.scope(
                            state: \.settings,
                            action: MainAppFeature.Action.settings
                        )
                    )
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(MainAppFeature.State.Tab.settings)
                }
            }
        }
    }
}
