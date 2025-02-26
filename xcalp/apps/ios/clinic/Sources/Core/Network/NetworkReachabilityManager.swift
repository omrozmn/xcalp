import Foundation
import Network

public final class NetworkReachabilityManager {
    public static let shared = NetworkReachabilityManager()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xcalp.clinic.network")
    
    public func isReachable() async -> Bool {
        monitor.currentPath.status == .satisfied
    }
    
    init() {
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}