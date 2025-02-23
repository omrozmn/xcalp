import SwiftUI
import XcalpClinic
import ComposableArchitecture

@main
struct XcalpClinicApp: App {
    static let store: StoreOf<AppFeature> = Store(initialState: AppFeature.State()) {
        AppFeature()
            ._printChanges() // Helpful for debugging
    }
    
    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
        }
    }
}
