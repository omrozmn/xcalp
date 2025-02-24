import Combine
import ComposableArchitecture
import Foundation
import SwiftUI

@MainActor
final class AnalyticsDashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var memoryUsageData: [MetricDataPoint] = []
    @Published private(set) var scanQualityData: [QualityDataPoint] = []
    @Published private(set) var templateUsageData: [TemplateUsagePoint] = []
    @Published private(set) var currentMemoryUsage: Double = 0
    @Published private(set) var currentFrameRate: Double = 0
    @Published private(set) var scanSuccessRate: Double = 0
    @Published private(set) var averageScanTime: Double = 0
    @Published private(set) var securityMetrics: SecurityMetrics = .init()
    @Published private(set) var isMemoryUsageHigh: Bool = false
    
    // MARK: - Computed Properties
    var memoryTrend: MetricTrend {
        guard let last = memoryUsageData.last?.value,
              let previous = memoryUsageData.dropLast().last?.value else {
            return .neutral
        }
        return last > previous ? .declining : .improving
    }
    
    var frameRateTrend: MetricTrend {
        currentFrameRate >= 30 ? .improving : .declining
    }
    
    var scanSuccessTrend: MetricTrend {
        scanSuccessRate >= 0.9 ? .improving : .declining
    }
    
    var scanDurationTrend: MetricTrend {
        averageScanTime <= 5.0 ? .improving : .declining
    }
    
    var securityTrend: MetricTrend {
        securityMetrics.isCompliant ? .improving : .declining
    }
    
    var authenticationStatus: String {
        securityMetrics.isAuthenticationValid ? "Valid" : "Invalid"
    }
    
    var encryptionStatus: String {
        securityMetrics.isEncryptionEnabled ? "Enabled" : "Disabled"
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let updateInterval: TimeInterval = 5 // 5 seconds
    private let maxDataPoints = 60 // 5 minutes of data
    
    @Dependency(\.resourceClient) var resourceClient
    @Dependency(\.analyticsClient) var analyticsClient
    @Dependency(\.securityClient) var securityClient
    
    // MARK: - Initialization
    init() {
        setupMetricsCollection()
    }
    
    // MARK: - Public Methods
    func startMetricsCollection() async {
        // Start collecting real-time metrics
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.collectPerformanceMetrics() }
            group.addTask { await self.collectScanningMetrics() }
            group.addTask { await self.collectSecurityMetrics() }
            group.addTask { await self.collectUsageMetrics() }
        }
    }
    
    func refreshData() async {
        // Refresh all metrics data
        memoryUsageData = await analyticsClient.getMemoryUsageHistory()
        scanQualityData = await analyticsClient.getScanQualityData()
        templateUsageData = await analyticsClient.getTemplateUsageData()
        currentMemoryUsage = resourceClient.currentUsage().currentMemory / 1_000_000 // Convert to MB
        currentFrameRate = await analyticsClient.getCurrentFrameRate()
        scanSuccessRate = await analyticsClient.getScanSuccessRate()
        averageScanTime = await analyticsClient.getAverageScanTime()
        securityMetrics = await securityClient.getCurrentSecurityStatus()
        
        isMemoryUsageHigh = currentMemoryUsage > resourceClient.quotaLimits().maxMemory * 0.8
    }
    
    // MARK: - Private Methods
    private func setupMetricsCollection() {
        // Setup timers for periodic updates
        Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.updateMetrics() }
            }
            .store(in: &cancellables)
    }
    
    private func updateMetrics() async {
        await refreshData()
        
        // Maintain data point limits
        if memoryUsageData.count > maxDataPoints {
            memoryUsageData.removeFirst(memoryUsageData.count - maxDataPoints)
        }
    }
    
    private func collectPerformanceMetrics() async {
        for await metrics in resourceClient.performanceMetricsStream() {
            currentMemoryUsage = Double(metrics.memory) / 1_000_000 // Convert to MB
            currentFrameRate = metrics.frameRate
            memoryUsageData.append(MetricDataPoint(timestamp: Date(), value: currentMemoryUsage))
            isMemoryUsageHigh = currentMemoryUsage > Double(resourceClient.quotaLimits().maxMemory) * 0.8
        }
    }
    
    private func collectScanningMetrics() async {
        for await metrics in analyticsClient.scanningMetricsStream() {
            scanSuccessRate = metrics.successRate
            averageScanTime = metrics.averageDuration
            scanQualityData = metrics.qualityDistribution
        }
    }
    
    private func collectSecurityMetrics() async {
        for await metrics in securityClient.securityMetricsStream() {
            securityMetrics = metrics
        }
    }
    
    private func collectUsageMetrics() async {
        for await metrics in analyticsClient.usageMetricsStream() {
            templateUsageData = metrics.templateUsage
        }
    }
}

// MARK: - Data Models
struct MetricDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct QualityDataPoint: Identifiable {
    let id = UUID()
    let quality: String
    let count: Int
}

struct TemplateUsagePoint: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct SecurityMetrics {
    var isCompliant: Bool = false
    var isAuthenticationValid: Bool = false
    var isEncryptionEnabled: Bool = false
    var lastUpdateTime: Date = Date()
    var securityScore: Double = 0
    var vulnerabilitiesCount: Int = 0
}
