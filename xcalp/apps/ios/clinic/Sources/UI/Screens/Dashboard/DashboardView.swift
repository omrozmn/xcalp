import SwiftUI
import ComposableArchitecture

public struct DashboardView: View {
    let store: StoreOf<DashboardFeature>
    
    public init(store: StoreOf<DashboardFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ScrollView {
                VStack(spacing: 16) {
                    ConnectionStatusView(isOnline: viewStore.isOnline)
                        .accessibility(label: Text(viewStore.isOnline ? "System online" : "System offline"))
                        .accessibility(hint: Text(viewStore.isOnline ? "All features available" : "Limited features available"))
                    
                    if viewStore.isRefreshing && viewStore.todaySchedule.isEmpty {
                        LoadingView()
                    } else {
                        ContentView(viewStore: viewStore)
                    }
                }
                .padding()
                .animation(.easeInOut, value: viewStore.isRefreshing)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileButton(viewStore: viewStore)
                }
            }
            .refreshable {
                HapticFeedback.light.play()
                await viewStore.send(.refresh, while: \.isRefreshing)
            }
            .alert(
                "Error",
                isPresented: viewStore.binding(
                    get: { $0.errorMessage != nil },
                    send: DashboardFeature.Action.dismissError
                ),
                presenting: viewStore.errorMessage
            ) { _ in
                Button("OK") { viewStore.send(.dismissError) }
                if viewStore.isOnline {
                    Button("Retry") { viewStore.send(.refresh) }
                }
            } message: { message in
                Text(message)
            }
            .onAppear { viewStore.send(.onAppear) }
        }
    }
}

// MARK: - Subviews
private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            Text("Loading dashboard data...")
                .xcalpText(.body)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

private struct ContentView: View {
    let viewStore: ViewStore<DashboardFeature.State, DashboardFeature.Action>
    
    var body: some View {
        VStack(spacing: 16) {
            TodayScheduleSection(appointments: viewStore.todaySchedule)
                .accessibility(label: Text("Today's schedule"))
            
            RecentPatientsSection(patients: viewStore.recentPatients)
                .accessibility(label: Text("Recent patients"))
            
            QuickActionsGrid(actions: viewStore.quickActions) { action in
                HapticFeedback.selection.play()
                viewStore.send(.quickActionSelected(action))
            }
            .accessibility(label: Text("Quick actions"))
            
            StatisticsPanel(stats: viewStore.statistics)
                .accessibility(label: Text("Clinic statistics"))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private struct ProfileButton: View {
    let viewStore: ViewStore<DashboardFeature.State, DashboardFeature.Action>
    
    var body: some View {
        Button {
            HapticFeedback.light.play()
            viewStore.send(.profileButtonTapped)
        } label: {
            Image(systemName: "person.circle")
                .accessibility(label: Text("Profile settings"))
        }
    }
}

private struct ConnectionStatusView: View {
    let isOnline: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(isOnline ? "Online" : "Offline")
                .xcalpText(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }
}

private struct TodayScheduleSection: View {
    let appointments: [DashboardFeature.Appointment]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Schedule")
                .xcalpText(.h2)
            
            ForEach(appointments) { appointment in
                AppointmentRow(appointment: appointment)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct RecentPatientsSection: View {
    let patients: [DashboardFeature.RecentPatient]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Patients")
                .xcalpText(.h2)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(patients) { patient in
                        RecentPatientCard(patient: patient)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct QuickActionsGrid: View {
    let actions: [DashboardFeature.QuickAction]
    let onAction: (DashboardFeature.QuickAction) -> Void
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    VStack {
                        Image(systemName: action.iconName)
                            .font(.title)
                        Text(action.title)
                            .xcalpText(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                }
            }
        }
    }
}

private struct StatisticsPanel: View {
    let stats: [DashboardFeature.Statistic]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .xcalpText(.h2)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                ForEach(stats) { stat in
                    StatisticCard(statistic: stat)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct AppointmentRow: View {
    let appointment: DashboardFeature.Appointment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.patientName)
                    .xcalpText(.body)
                Text(appointment.type)
                    .xcalpText(.caption)
            }
            
            Spacer()
            
            Text(appointment.time)
                .xcalpText(.caption)
        }
        .padding(.vertical, 8)
    }
}

private struct RecentPatientCard: View {
    let patient: DashboardFeature.RecentPatient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.name)
                .xcalpText(.body)
            Text(patient.lastVisit)
                .xcalpText(.caption)
        }
        .frame(width: 160)
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct StatisticCard: View {
    let statistic: DashboardFeature.Statistic
    
    var body: some View {
        VStack(spacing: 8) {
            Text(statistic.value)
                .xcalpText(.h3)
            Text(statistic.title)
                .xcalpText(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}