import SwiftUI

public struct MainView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            NavigationView {
                PatientListView()
            }
            .tabItem {
                Label("Patients", systemImage: "person.2")
            }
            
            NavigationView {
                Text("Scans")
            }
            .tabItem {
                Label("Scans", systemImage: "camera.viewfinder")
            }
            
            NavigationView {
                Text("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .accentColor(XcalpColors.vibrantBlue)
    }
}
