import Combine
import CoreData
import Foundation
import Network

public actor DashboardService {
    public static let shared = DashboardService()
    
    private let networkManager: NetworkManager
    private let coreDataStack: CoreDataStack
    private let performanceMonitor: PerformanceMonitor
    private let reachability: NetworkReachabilityManager
    
    private var dashboardUpdateTimer: Task<Void, Never>?
    private var retryBackoff: TimeInterval = 1.0
    
    public init(
        networkManager: NetworkManager = .shared,
        coreDataStack: CoreDataStack = .shared,
        performanceMonitor: PerformanceMonitor = .shared,
        reachability: NetworkReachabilityManager = .shared
    ) {
        self.networkManager = networkManager
        self.coreDataStack = coreDataStack
        self.performanceMonitor = performanceMonitor
        self.reachability = reachability
        Task { await setupBackgroundUpdates() }
    }
    
    private func setupBackgroundUpdates() {
        dashboardUpdateTimer = Task {
            while !Task.isCancelled {
                if await reachability.isReachable() {
                    do {
                        let data = try await getDashboardData()
                        await cacheDashboardData(summary: data.0, stats: data.1)
                        retryBackoff = AppConfiguration.Networking.retryDelay // Reset backoff on success
                    } catch {
                        retryBackoff = min(retryBackoff * 2, 60) // Exponential backoff up to 1 minute
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(retryBackoff * 1_000_000_000))
            }
        }
    }
    
    public struct DashboardSummary: Codable {
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
    
    public struct DashboardStats: Codable {
        let totalPatients: Int
        let monthlyScans: Int
        let successRate: Double
        let activePlans: Int
        let performanceMetrics: PerformanceMetrics
        
        struct PerformanceMetrics: Codable {
            let cpuUsage: Double
            let memoryUsage: UInt64
            let gpuUtilization: Double
            let frameRate: Double
        }
    }
    
    public func getDashboardData() async throws -> (DashboardSummary, DashboardStats) {
        do {
            let metrics = performanceMonitor.reportResourceMetrics()
            
            async let summaryRequest = networkManager.request(
                ClinicEndpoint.getDashboardSummary,
                timeoutInterval: AppConfiguration.Networking.timeoutInterval
            ) as DashboardSummary
            
            async let statsRequest = networkManager.request(
                ClinicEndpoint.getDashboardStats,
                timeoutInterval: AppConfiguration.Networking.timeoutInterval
            ) as DashboardStats
            
            let result = try await (summaryRequest, statsRequest)
            
            // Cache successful response
            await cacheDashboardData(summary: result.0, stats: result.1)
            
            return result
        } catch {
            // On network error, try to load cached data
            if let cached = try? await loadCachedDashboardData() {
                return cached
            }
            throw error
        }
    }
    
    private func cacheDashboardData(summary: DashboardSummary, stats: DashboardStats) async {
        let context = coreDataStack.backgroundContext
        
        await context.perform {
            let cache = DashboardCache(context: context)
            cache.timestamp = Date()
            cache.summary = try? JSONEncoder().encode(summary)
            cache.stats = try? JSONEncoder().encode(stats)
            
            try? context.save()
        }
    }
    
    private func loadCachedDashboardData() async throws -> (DashboardSummary, DashboardStats)? {
        let context = coreDataStack.backgroundContext
        
        return try await context.perform {
            guard let cache = try DashboardCache.fetchMostRecent(in: context),
                  let summaryData = cache.summary,
                  let statsData = cache.stats,
                  let summary = try? JSONDecoder().decode(DashboardSummary.self, from: summaryData),
                  let stats = try? JSONDecoder().decode(DashboardStats.self, from: statsData),
                  cache.timestamp?.timeIntervalSinceNow ?? -.infinity > -AppConfiguration.Cache.maxAge
            else {
                return nil
            }
            
            return (summary, stats)
        }
    }
    
    deinit {
        dashboardUpdateTimer?.cancel()
    }
}