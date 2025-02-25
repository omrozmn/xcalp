import Dependencies
import Foundation

public struct NetworkMonitorClient {
    public var isConnected: () -> Bool
    public var connectionType: () -> NetworkMonitor.ConnectionType
    public var observeConnectionStatus: () -> AsyncStream<Bool>
}

extension NetworkMonitorClient: DependencyKey {
    public static let liveValue = NetworkMonitorClient(
        isConnected: { NetworkMonitor.shared.isConnected },
        connectionType: { NetworkMonitor.shared.connectionType },
        observeConnectionStatus: {
            AsyncStream { continuation in
                Task { @MainActor in
                    for await isConnected in NetworkMonitor.shared.$isConnected.values {
                        continuation.yield(isConnected)
                    }
                }
            }
        }
    )
}

extension DependencyValues {
    public var networkMonitor: NetworkMonitorClient {
        get { self[NetworkMonitorClient.self] }
        set { self[NetworkMonitorClient.self] = newValue }
    }
}