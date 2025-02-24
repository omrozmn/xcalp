import SwiftUI\n
import XcalpClinic
import ComposableArchitecture

@main
struct XcalpClinicApp: App {
    let store: StoreOf<AppFeature> = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    
    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
