import ComposableArchitecture
import Foundation
import Features

public struct DashboardFeature: Reducer {
    public struct State: Equatable {
        public var isOnline: Bool = true
        public var isRefreshing: Bool = false
        public var todaySchedule: [Appointment] = []
        public var recentPatients: [RecentPatient] = []
        public var quickActions: [QuickAction] = []
        public var statistics: [Statistic] = []
        
        public init() {
            // Default quick actions
            quickActions = [
                .init(id: "new_scan", title: "New Scan", iconName: "camera.fill"),
                .init(id: "new_patient", title: "New Patient", iconName: "person.badge.plus"),
                .init(id: "start_treatment", title: "Treatment", iconName: "chart.bar.doc.horizontal"),
                .init(id: "analysis", title: "Analysis", iconName: "waveform.path.ecg")
            ]
        }
    }
    
    public enum Action: Equatable {
        case onAppear
        case refresh
        case dashboardResponse(TaskResult<(DashboardService.DashboardSummary, DashboardService.DashboardStats)>)
        case quickActionSelected(QuickAction)
        case profileButtonTapped
        case connectionStatusChanged(Bool)
        case webSocketEvent(WebSocketService.Event)
    }
    
    @Dependency(\.continuousClock) var clock
    @Dependency(\.networkMonitor) var networkMonitor
    private let dashboardService = DashboardService.shared
    private let webSocketService = WebSocketService.shared
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Start observing network status and WebSocket events
                return .merge(
                    .send(.refresh),
                    .run { send in
                        await webSocketService.connect()
                        for await isConnected in networkMonitor.observeConnectionStatus() {
                            if isConnected {
                                await webSocketService.connect()
                            } else {
                                await webSocketService.disconnect()
                            }
                            await send(.connectionStatusChanged(isConnected))
                        }
                    },
                    .run { send in
                        for await event in await webSocketService.observeEvents() {
                            await send(.webSocketEvent(event))
                        }
                    }
                )
                
            case .refresh:
                // Only attempt refresh if online
                guard networkMonitor.isConnected() else {
                    state.isRefreshing = false
                    return .none
                }
                
                state.isRefreshing = true
                return .run { send in
                    await send(.dashboardResponse(TaskResult {
                        try await dashboardService.getDashboardData()
                    }))
                }
                
            case let .dashboardResponse(.success((summary, stats))):
                state.isRefreshing = false
                state.todaySchedule = summary.appointments.map {
                    Appointment(
                        id: UUID(uuidString: $0.id) ?? UUID(),
                        patientName: $0.patientName,
                        type: $0.type,
                        time: $0.time
                    )
                }
                state.recentPatients = summary.recentPatients.map {
                    RecentPatient(
                        id: UUID(uuidString: $0.id) ?? UUID(),
                        name: $0.name,
                        lastVisit: DateFormatter.localizedString(from: $0.lastVisit, dateStyle: .medium, timeStyle: .none)
                    )
                }
                state.statistics = [
                    .init(id: UUID(), title: "Total Patients", value: "\(stats.totalPatients)"),
                    .init(id: UUID(), title: "Monthly Scans", value: "\(stats.monthlyScans)"),
                    .init(id: UUID(), title: "Success Rate", value: "\(Int(stats.successRate))%"),
                    .init(id: UUID(), title: "Active Plans", value: "\(stats.activePlans)")
                ]
                return .none
                
            case .dashboardResponse(.failure):
                state.isRefreshing = false
                return .none
                
            case let .quickActionSelected(action):
                let coordinator = NavigationCoordinator.shared
                switch action.id {
                case "new_scan":
                    coordinator.navigate(to: DashboardDestination.newScan)
                case "new_patient":
                    coordinator.navigate(to: DashboardDestination.newPatient)
                case "start_treatment":
                    coordinator.navigate(to: DashboardDestination.treatment)
                case "analysis":
                    coordinator.navigate(to: DashboardDestination.analysis)
                default:
                    break
                }
                return .none
                
            case .profileButtonTapped:
                NavigationCoordinator.shared.presentSheet(.settings)
                return .none
                
            case let .connectionStatusChanged(isOnline):
                state.isOnline = isOnline
                // Refresh data when coming back online
                if isOnline {
                    return .send(.refresh)
                }
                return .none
                
            case let .webSocketEvent(event):
                switch event {
                case .dashboardUpdate(let summary):
                    state.todaySchedule = summary.appointments.map {
                        Appointment(
                            id: UUID(uuidString: $0.id) ?? UUID(),
                            patientName: $0.patientName,
                            type: $0.type,
                            time: $0.time
                        )
                    }
                    state.recentPatients = summary.recentPatients.map {
                        RecentPatient(
                            id: UUID(uuidString: $0.id) ?? UUID(),
                            name: $0.name,
                            lastVisit: DateFormatter.localizedString(from: $0.lastVisit, dateStyle: .medium, timeStyle: .none)
                        )
                    }
                    return .none
                    
                case .notification:
                    // Handle notifications in a separate feature
                    return .none
                }
            }
        }
    }
}

// MARK: - Models
extension DashboardFeature {
    public struct Appointment: Equatable, Identifiable {
        public let id: UUID
        public let patientName: String
        public let type: String
        public let time: String
        
        public init(id: UUID, patientName: String, type: String, time: String) {
            self.id = id
            self.patientName = patientName
            self.type = type
            self.time = time
        }
    }
    
    public struct RecentPatient: Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let lastVisit: String
        
        public init(id: UUID, name: String, lastVisit: String) {
            self.id = id
            self.name = name
            self.lastVisit = lastVisit
        }
    }
    
    public struct QuickAction: Equatable, Identifiable {
        public var id: String
        public let title: String
        public let iconName: String
        
        public init(id: String, title: String, iconName: String) {
            self.id = id
            self.title = title
            self.iconName = iconName
        }
    }
    
    public struct Statistic: Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let value: String
        
        public init(id: UUID, title: String, value: String) {
            self.id = id
            self.title = title
            self.value = value
        }
    }
}