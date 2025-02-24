import Combine
import Foundation
import Network

public final class ConnectionQualityService {
    public static let shared = ConnectionQualityService()
    
    private let networkMonitor: NetworkMonitor
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ConnectionQuality")
    private var cancellables = Set<AnyCancellable>()
    
    @Published public private(set) var qualityLevel: ConnectionQuality = .unknown
    @Published public private(set) var recommendations: [ConnectionRecommendation] = []
    
    private let qualityThresholds = QualityThresholds(
        latencyThresholds: [
            .excellent: 0.1,  // 100ms
            .good: 0.3,      // 300ms
            .fair: 0.5,      // 500ms
            .poor: 1.0       // 1s
        ],
        throughputThresholds: [
            .excellent: 5_242_880,    // 5MB/s
            .good: 2_097_152,         // 2MB/s
            .fair: 1_048_576,         // 1MB/s
            .poor: 524_288            // 512KB/s
        ]
    )
    
    private init(networkMonitor: NetworkMonitor = .shared) {
        self.networkMonitor = networkMonitor
        setupObservers()
    }
    
    private func setupObservers() {
        // Monitor network status changes
        networkMonitor.$status
            .combineLatest(networkMonitor.$isExpensive, networkMonitor.$isConstrained)
            .sink { [weak self] status, isExpensive, isConstrained in
                self?.evaluateConnectionQuality(
                    status: status,
                    isExpensive: isExpensive,
                    isConstrained: isConstrained
                )
            }
            .store(in: &cancellables)
    }
    
    private func evaluateConnectionQuality(status: NetworkStatus, isExpensive: Bool, isConstrained: Bool) {
        guard status == .connected else {
            qualityLevel = .unknown
            recommendations = []
            return
        }
        
        let latency = networkMonitor.averageLatency
        let throughput = networkMonitor.averageThroughput
        
        // Determine quality level based on metrics
        let latencyQuality = determineQualityLevel(
            value: latency,
            thresholds: qualityThresholds.latencyThresholds,
            inversed: true
        )
        
        let throughputQuality = determineQualityLevel(
            value: throughput,
            thresholds: qualityThresholds.throughputThresholds,
            inversed: false
        )
        
        // Use the worse of the two metrics
        qualityLevel = min(latencyQuality, throughputQuality)
        
        // Generate recommendations based on current state
        updateRecommendations(
            latency: latency,
            throughput: throughput,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
        
        logQualityUpdate()
    }
    
    private func determineQualityLevel(
        value: Double,
        thresholds: [ConnectionQuality: Double],
        inversed: Bool
    ) -> ConnectionQuality {
        let comparator: (Double, Double) -> Bool = inversed ? (>) : (<)
        
        if comparator(value, thresholds[.poor] ?? 0) {
            return .poor
        } else if comparator(value, thresholds[.fair] ?? 0) {
            return .fair
        } else if comparator(value, thresholds[.good] ?? 0) {
            return .good
        } else {
            return .excellent
        }
    }
    
    private func updateRecommendations(
        latency: TimeInterval,
        throughput: Double,
        isExpensive: Bool,
        isConstrained: Bool
    ) {
        var newRecommendations: [ConnectionRecommendation] = []
        
        // Add recommendations based on metrics
        if latency > qualityThresholds.latencyThresholds[.fair] ?? 0 {
            newRecommendations.append(.reduceDataSize)
        }
        
        if throughput < qualityThresholds.throughputThresholds[.fair] ?? 0 {
            newRecommendations.append(.useLowerQuality)
        }
        
        if isExpensive {
            newRecommendations.append(.waitForWiFi)
        }
        
        if isConstrained {
            newRecommendations.append(.optimizeDataUsage)
        }
        
        recommendations = newRecommendations
    }
    
    private func logQualityUpdate() {
        let qualityInfo = """
            Connection Quality Update:
            Quality Level: \(qualityLevel)
            Latency: \(String(format: "%.3f", networkMonitor.averageLatency))s
            Throughput: \(String(format: "%.2f", networkMonitor.averageThroughput / 1024 / 1024))MB/s
            Recommendations: \(recommendations.map { $0.rawValue }.joined(separator: ", "))
            """
        
        logger.info("\(qualityInfo)")
    }
}

// MARK: - Supporting Types

public enum ConnectionQuality: Int, Comparable {
    case unknown = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4
    
    public static func < (lhs: ConnectionQuality, rhs: ConnectionQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ConnectionRecommendation: String {
    case reduceDataSize = "Reduce data size"
    case useLowerQuality = "Use lower quality"
    case waitForWiFi = "Wait for WiFi"
    case optimizeDataUsage = "Optimize data usage"
}

private struct QualityThresholds {
    let latencyThresholds: [ConnectionQuality: TimeInterval]
    let throughputThresholds: [ConnectionQuality: Double]
}
