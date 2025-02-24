import ComposableArchitecture
import SwiftUI

public struct AppView: View {
    let store: StoreOf<AppFeature>
    
    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.mainApp != nil {
                    MainAppView(
                        store: store.scope(
                            state: \.mainApp,
                            action: AppFeature.Action.mainApp
                        )
                    )
                } else {
                    AuthenticationView(
                        store: store.scope(
                            state: \.auth,
                            action: AppFeature.Action.auth
                        )
                    )
                }
            }
        }
    }
}
