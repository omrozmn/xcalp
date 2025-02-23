import Foundation
import os.log

public enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingError
    case noInternet
    case timeout(retryCount: Int)
    case rateLimited(retryAfter: TimeInterval)
    case requestCancelled
    case unknown(Error?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized access"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .noInternet:
            return "No internet connection"
        case .timeout(let retryCount):
            return "Request timed out (Attempt \(retryCount))"
        case .rateLimited(let retryAfter):
            return "Rate limited. Try again in \(Int(retryAfter)) seconds"
        case .requestCancelled:
            return "Request was cancelled"
        case .unknown(let error):
            return error?.localizedDescription ?? "Unknown error occurred"
        }
    }
}

public final class NetworkManager {
    public static let shared = NetworkManager()
    
    private let session: URLSession
    private let hipaaLogger = HIPAALogger.shared
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Network")
    
    // Network configuration
    private let defaultTimeout: TimeInterval = 30
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2
    private let progressiveRetryMultiplier: Double = 1.5
    private let networkQualityAdjustment: Double = 1.5
    
    // Rate limiting
    private var rateLimitRemainingCalls: Int = 100  // Default limit
    private var rateLimitResetTime: Date = Date()
    
    private var adjustedTimeout: TimeInterval {
        let networkQuality = NetworkMonitor.shared.averageLatency
        let multiplier = networkQuality > 1.0 ? networkQualityAdjustment : 1.0
        return defaultTimeout * multiplier
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = adjustedTimeout
        config.timeoutIntervalForResource = adjustedTimeout * 2
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 5
        session = URLSession(configuration: config)
    }
    
    public func request<T: Codable>(_ endpoint: APIEndpoint, retryCount: Int = 0) async throws -> T {
        // Update timeout based on current network conditions
        session.configuration.timeoutIntervalForRequest = adjustedTimeout
        session.configuration.timeoutIntervalForResource = adjustedTimeout * 2
        
        // Check rate limiting
        if rateLimitRemainingCalls <= 0 && Date() < rateLimitResetTime {
            throw NetworkError.rateLimited(retryAfter: rateLimitResetTime.timeIntervalSinceNow)
        }
        
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication
        if let token = try? AuthenticationManager.shared.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add request body
        if let body = endpoint.body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            // Update rate limiting info
            updateRateLimits(from: httpResponse)
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(T.self, from: data)
                } catch {
                    logError(.decodingError, endpoint: endpoint, error: error)
                    throw NetworkError.decodingError
                }
                
            case 401:
                logError(.unauthorized, endpoint: endpoint)
                throw NetworkError.unauthorized
                
            case 429:  // Rate Limited
                let retryAfter = TimeInterval(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                rateLimitResetTime = Date().addingTimeInterval(retryAfter)
                throw NetworkError.rateLimited(retryAfter: retryAfter)
                
            case 500...599:
                logError(.serverError(httpResponse.statusCode), endpoint: endpoint)
                
                // Retry server errors with backoff
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * pow(progressiveRetryMultiplier, Double(retryCount)) * 1_000_000_000))
                    return try await request(endpoint, retryCount: retryCount + 1)
                }
                
                throw NetworkError.serverError(httpResponse.statusCode)
                
            default:
                throw NetworkError.unknown(nil)
            }
            
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                throw NetworkError.noInternet
                
            case .timedOut:
                logError(.timeout(retryCount: retryCount), endpoint: endpoint)
                
                // Retry timeouts with backoff
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * pow(progressiveRetryMultiplier, Double(retryCount)) * 1_000_000_000))
                    return try await request(endpoint, retryCount: retryCount + 1)
                }
                
                throw NetworkError.timeout(retryCount: retryCount)
                
            case .cancelled:
                throw NetworkError.requestCancelled
                
            default:
                throw NetworkError.unknown(error)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateRateLimits(from response: HTTPURLResponse) {
        if let remaining = Int(response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? ""),
           let resetTime = Double(response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "") {
            rateLimitRemainingCalls = remaining
            rateLimitResetTime = Date(timeIntervalSince1970: resetTime)
        }
    }
    
    private func logError(_ error: NetworkError, endpoint: APIEndpoint, error originalError: Error? = nil) {
        let userID = AuthenticationManager.shared.currentUserID ?? "UNKNOWN"
        let errorDetails = """
            Endpoint: \(endpoint.path)
            Error: \(error.localizedDescription)
            Original Error: \(originalError?.localizedDescription ?? "N/A")
            User ID: \(userID)
            """
        
        hipaaLogger.log(
            type: .systemError,
            action: "Network Error",
            userID: userID,
            details: errorDetails
        )
        
        logger.error("\(errorDetails)")
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

public protocol APIEndpoint {
    var baseURL: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var body: [String: Any]? { get }
    var url: URL? { get }
}

public extension APIEndpoint {
    var url: URL? {
        URL(string: baseURL + path)
    }
}
