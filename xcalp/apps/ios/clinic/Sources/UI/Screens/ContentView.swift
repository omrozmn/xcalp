import SwiftUI
import ComposableArchitecture

public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Welcome to Xcalp Clinic")
                        .font(.headline)
                } header: {
                    Text("Dashboard")
                }
            }
            .navigationTitle("Xcalp Clinic")
        }
    }
}
