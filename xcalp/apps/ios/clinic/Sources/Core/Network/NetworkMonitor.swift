import Foundation
import Network
import os.log
import Combine

public enum NetworkStatus: String {
    case connected
    case disconnected
    case restricted
    case expensive  // Cellular or hotspot
    case constrained  // Low data mode
    case unknown
}

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    @Published public private(set) var status: NetworkStatus = .unknown
    @Published public private(set) var isConnected = false
    @Published public private(set) var isExpensive = false
    @Published public private(set) var isConstrained = false
    
    private let monitor: NWPathMonitor
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Network")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.network", qos: .utility)
    
    // Network quality metrics
    private var latencyHistory: [TimeInterval] = []
    private var throughputHistory: [Double] = []
    private let maxHistoryItems = 10
    
    public var averageLatency: TimeInterval {
        guard !latencyHistory.isEmpty else { return 0 }
        return latencyHistory.reduce(0, +) / Double(latencyHistory.count)
    }
    
    public var averageThroughput: Double {
        guard !throughputHistory.isEmpty else { return 0 }
        return throughputHistory.reduce(0, +) / Double(throughputHistory.count)
    }
    
    private init() {
        monitor = NWPathMonitor()
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.updateNetworkStatus(path)
                self.logNetworkChange(path)
                self.checkNetworkQuality(path)
            }
        }
        
        monitor.start(queue: queue)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        switch path.status {
        case .satisfied:
            self.status = .connected
            self.isConnected = true
        case .unsatisfied:
            self.status = .disconnected
            self.isConnected = false
        case .requiresConnection:
            self.status = .restricted
            self.isConnected = false
        @unknown default:
            self.status = .unknown
            self.isConnected = false
        }
        
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained
    }
    
    private func logNetworkChange(_ path: NWPath) {
        let interfaces = path.availableInterfaces.map { $0.name }.joined(separator: ", ")
        let status = """
            Network Status: \(status.rawValue)
            Connected: \(isConnected)
            Expensive: \(isExpensive)
            Constrained: \(isConstrained)
            Interfaces: \(interfaces)
            """
        
        logger.info("\(status)")
    }
    
    private func checkNetworkQuality(_ path: NWPath) {
        // Measure latency
        let startTime = Date()
        let url = URL(string: "https://www.apple.com")!
        
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            guard let self = self else { return }
            
            let latency = Date().timeIntervalSince(startTime)
            self.latencyHistory.append(latency)
            
            // Keep history within limits
            if self.latencyHistory.count > self.maxHistoryItems {
                self.latencyHistory.removeFirst()
            }
            
            // Log if latency is high
            if latency > 1.0 {  // More than 1 second
                self.logger.warning("High latency detected: \(latency) seconds")
            }
        }.resume()
    }
    
    public func measureThroughput(completion: @escaping (Double) -> Void) {
        let sampleSize = 1024 * 1024  // 1MB
        let url = URL(string: "https://speed.cloudflare.com/__down")!
        let startTime = Date()
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data else {
                completion(0)
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let throughput = Double(data.count) / elapsed  // bytes per second
            
            self.throughputHistory.append(throughput)
            
            // Keep history within limits
            if self.throughputHistory.count > self.maxHistoryItems {
                self.throughputHistory.removeFirst()
            }
            
            completion(throughput)
        }.resume()
    }
    
    public func isNetworkQualitySufficient() -> Bool {
        let minAcceptableLatency: TimeInterval = 0.5  // 500ms
        let minAcceptableThroughput: Double = 1024 * 1024  // 1MB/s
        
        return averageLatency <= minAcceptableLatency && averageThroughput >= minAcceptableThroughput
    }
    
    deinit {
        monitor.cancel()
    }
}