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
    private let minTimeout: TimeInterval = 10
    private let maxTimeout: TimeInterval = 60
    
    // Rate limiting and quality tracking
    private var rateLimitRemainingCalls: Int = 100
    private var rateLimitResetTime: Date = Date()
    private var recentTimeouts: [Date] = []
    private var activeRequests: Set<URLSessionTask> = []
    private let timeoutWindowDuration: TimeInterval = 300
    private let maxTimeoutsBeforeAdaption = 3
    private let taskQueue = OperationQueue()
    private let backgroundTaskManager = BackgroundTaskManager.shared
    
    private var adjustedTimeout: TimeInterval {
        let networkQuality = NetworkMonitor.shared.averageLatency
        let baseTimeout = defaultTimeout * (networkQuality > 1.0 ? networkQualityAdjustment : 1.0)
        
        // Adjust based on recent timeouts
        let recentTimeoutCount = recentTimeouts.filter { 
            Date().timeIntervalSince($0) < timeoutWindowDuration 
        }.count
        
        let timeoutMultiplier = 1.0 + (Double(recentTimeoutCount) * 0.25)
        let adjustedValue = baseTimeout * timeoutMultiplier
        
        return max(minTimeout, min(maxTimeout, adjustedValue))
    }
    
    private init() {
        taskQueue.maxConcurrentOperationCount = 4
        taskQueue.qualityOfService = .userInitiated
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 5
        config.timeoutIntervalForRequest = adjustedTimeout
        config.timeoutIntervalForResource = adjustedTimeout * 2
        
        session = URLSession(configuration: config)
    }
    
    public func request<T: Codable>(_ endpoint: APIEndpoint, retryCount: Int = 0) async throws -> T {
        // Register background task
        let taskID = await backgroundTaskManager.beginTask("networkRequest")
        defer { backgroundTaskManager.endTask(taskID) }
        
        // Update timeout dynamically
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
        request.setValue("\(Date().timeIntervalSince1970)", forHTTPHeaderField: "X-Request-Start")
        
        if let token = try? AuthenticationManager.shared.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = endpoint.body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let task = session.dataTask(with: request)
            activeRequests.insert(task)
            defer { activeRequests.remove(task) }
            
            let (data, response) = try await withCheckedThrowingContinuation { continuation in
                task.resume()
                
                // Set up task completion handler
                taskQueue.addOperation {
                    if let error = task.error {
                        continuation.resume(throwing: error)
                    } else if let data = task.response, let response = task.response {
                        continuation.resume(returning: (data, response))
                    }
                }
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            // Log request duration
            if let startTime = Double(httpResponse.value(forHTTPHeaderField: "X-Request-Start") ?? ""),
               startTime > 0 {
                let duration = Date().timeIntervalSince1970 - startTime
                logger.info("Request to \(endpoint.path) completed in \(String(format: "%.3f", duration))s")
            }
            
            // Handle response
            updateRateLimits(from: httpResponse)
            
            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: data)
                
            case 401:
                logError(.unauthorized, endpoint: endpoint)
                throw NetworkError.unauthorized
                
            case 429:
                let retryAfter = TimeInterval(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                rateLimitResetTime = Date().addingTimeInterval(retryAfter)
                throw NetworkError.rateLimited(retryAfter: retryAfter)
                
            case 500...599:
                logError(.serverError(httpResponse.statusCode), endpoint: endpoint)
                
                if retryCount < maxRetries {
                    try await handleTimeout(for: endpoint, retryCount: retryCount)
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
                if retryCount < maxRetries {
                    try await handleTimeout(for: endpoint, retryCount: retryCount)
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
    
    public func cancelAllRequests() {
        activeRequests.forEach { $0.cancel() }
        activeRequests.removeAll()
    }
    
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
    
    private func handleTimeout(for endpoint: APIEndpoint, retryCount: Int) async throws {
        recentTimeouts.append(Date())
        
        // Clean up old timeout records
        recentTimeouts = recentTimeouts.filter {
            Date().timeIntervalSince($0) < timeoutWindowDuration
        }
        
        logError(.timeout(retryCount: retryCount), endpoint: endpoint)
        
        if recentTimeouts.count >= maxTimeoutsBeforeAdaption {
            logger.warning("Multiple timeouts detected - adjusting network parameters")
            hipaaLogger.log(
                type: .systemWarning,
                action: "Network Adaptation",
                userID: "SYSTEM",
                details: "Multiple timeouts triggered network parameter adjustment"
            )
        }
        
        let backoffDelay = retryDelay * pow(progressiveRetryMultiplier, Double(retryCount))
        try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
    }
    
    public func request<T: Decodable>(_ endpoint: ClinicEndpoint, timeoutInterval: TimeInterval? = nil) async throws -> T {
        // Implementation
        fatalError("Not implemented")
    }
}

public enum ClinicEndpoint {
    case getDashboardSummary
    case getDashboardStats
    case getPatientProfile(patientId: String)
    case updatePatientProfile(patientId: String, profileData: [String: Any])
    case saveTreatmentPlan(patientId: String, planData: [String: Any])
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
