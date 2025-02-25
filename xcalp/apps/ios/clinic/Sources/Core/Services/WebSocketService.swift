import Foundation

public actor WebSocketService {
    public static let shared = WebSocketService()
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    
    public enum Event: Codable {
        case dashboardUpdate(DashboardService.DashboardSummary)
        case notification(title: String, message: String)
    }
    
    private init() {}
    
    public func connect() {
        guard !isConnected else { return }
        
        let url = URL(string: "wss://api.xcalp.com/v1/ws")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        
        receiveMessage()
    }
    
    public func disconnect() {
        webSocketTask?.cancel()
        webSocketTask = nil
        isConnected = false
    }
    
    public func observeEvents() -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                for await message in await receiveMessages() {
                    if case .data(let data) = message,
                       let event = try? JSONDecoder().decode(Event.self, from: data) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
        }
    }
    
    private func receiveMessages() -> AsyncStream<URLSessionWebSocketTask.Message> {
        AsyncStream { continuation in
            func receiveNext() {
                guard isConnected else {
                    continuation.finish()
                    return
                }
                
                webSocketTask?.receive { [weak self] result in
                    switch result {
                    case .success(let message):
                        continuation.yield(message)
                        self?.receiveNext()
                    case .failure:
                        continuation.finish()
                    }
                }
            }
            
            receiveNext()
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                self.receiveMessage()
            case .failure:
                self.disconnect()
            }
        }
    }
}