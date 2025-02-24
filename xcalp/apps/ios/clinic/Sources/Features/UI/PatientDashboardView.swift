import SwiftUI

struct PatientDashboardView: View {
    var body: some View {
        NavigationView {
            VStack {
                // Status bar
                HStack {
                    Text("Online") // Placeholder for online/offline indicator
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding()
                
                // Navigation bar
                HStack {
                    Text("Dashboard")
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    Button(action: {
                        // Profile button action
                    }) {
                        Image(systemName: "person.circle")
                            .font(.title)
                    }
                }
                .padding()
                
                // Content
                ScrollView {
                    VStack(alignment: .leading) {
                        // Today's Schedule
                        Text("Today's Schedule")
                            .font(.headline)
                            .padding(.top)
                        // Placeholder for schedule content
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 100)
                            .cornerRadius(10)
                            .padding(.bottom)
                        
                        // Recent Patients
                        Text("Recent Patients")
                            .font(.headline)
                        // Placeholder for recent patients content
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 100)
                            .cornerRadius(10)
                            .padding(.bottom)
                        
                        // Quick Actions
                        Text("Quick Actions")
                            .font(.headline)
                        // Placeholder for quick actions content
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 100)
                            .cornerRadius(10)
                            .padding(.bottom)
                        
                        // Statistics
                        Text("Statistics")
                            .font(.headline)
                        // Placeholder for statistics content
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 100)
                            .cornerRadius(10)
                            .padding(.bottom)
                    }
                    .padding()
                }
            }
        }
    }
}

struct PatientDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        PatientDashboardView()
    }
}
