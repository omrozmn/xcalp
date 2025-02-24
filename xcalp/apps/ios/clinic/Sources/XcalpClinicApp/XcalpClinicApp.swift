import SwiftUI

@main
struct XcalpClinicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            PatientDashboardView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Dashboard")
                }
            RegistrationScreenView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Register")
                }
        }
    }
}
