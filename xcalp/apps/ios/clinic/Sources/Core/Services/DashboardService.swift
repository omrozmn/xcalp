import Foundation

public actor DashboardService {
    public static let shared = DashboardService()
    private let networkManager: NetworkManager
    
    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }
    
    struct DashboardSummary: Codable {
        let appointments: [Appointment]
        let recentPatients: [RecentPatient]
        
        struct Appointment: Codable {
            let id: String
            let patientName: String
            let type: String
            let time: String
        }
        
        struct RecentPatient: Codable {
            let id: String
            let name: String
            let lastVisit: Date
        }
    }
    
    struct DashboardStats: Codable {
        let totalPatients: Int
        let monthlyScans: Int
        let successRate: Double
        let activePlans: Int
    }
    
    public func getDashboardData() async throws -> (DashboardSummary, DashboardStats) {
        async let summary = networkManager.request(ClinicEndpoint.getDashboardSummary) as DashboardSummary
        async let stats = networkManager.request(ClinicEndpoint.getDashboardStats) as DashboardStats
        return try await (summary, stats)
    }
}