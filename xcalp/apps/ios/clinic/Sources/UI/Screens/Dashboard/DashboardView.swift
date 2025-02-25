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
                    // Status bar
                    ConnectionStatusView(isOnline: viewStore.isOnline)
                    
                    // Today's Schedule
                    TodayScheduleSection(appointments: viewStore.todaySchedule)
                    
                    // Recent Patients
                    RecentPatientsSection(patients: viewStore.recentPatients)
                    
                    // Quick Actions
                    QuickActionsGrid(actions: viewStore.quickActions) { action in
                        viewStore.send(.quickActionSelected(action))
                    }
                    
                    // Statistics
                    StatisticsPanel(stats: viewStore.statistics)
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewStore.send(.profileButtonTapped)
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .refreshable {
                await viewStore.send(.refresh, while: \.isRefreshing)
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
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