import Foundation
import OSLog

/// Central error handling system for standardized error management
public final class ErrorHandler {
    public static let shared = ErrorHandler()
    
    private let analytics = AnalyticsService.shared
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ErrorHandler")
    
    private var errorObservers: [(XcalpError) -> Void] = []
    private var recentErrors: [XcalpError] = []
    private let maxStoredErrors = 50
    
    private init() {}
    
    /// Handle an error with proper logging and analytics
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Additional context about where the error occurred
    ///   - file: Source file where error occurred
    ///   - function: Function where error occurred
    ///   - line: Line number where error occurred
    /// - Returns: User-facing localized error
    public func handle(
        _ error: Error,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> LocalizedError {
        // Map to appropriate error type
        let appError: AppError
        
        switch error {
        case let securityError as SecurityError:
            appError = handleSecurityError(securityError)
            
        case let networkError as NetworkError:
            appError = handleNetworkError(networkError)
            
        case let storageError as SecureStorageService.StorageError:
            appError = handleStorageError(storageError)
            
        case let medicalError as HIPAAMedicalDataHandler.MedicalDataError:
            appError = handleMedicalError(medicalError)
            
        default:
            appError = .unknown(error)
        }
        
        // Log error with context
        var errorContext = context
        errorContext["file"] = file
        errorContext["function"] = function
        errorContext["line"] = line
        
        logError(appError, context: errorContext)
        
        return appError
    }
    
    /// Handle errors in async contexts with automatic retry
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts
    ///   - operation: The async operation to perform
    public func retry<T>(
        maxRetries: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempts = 0
        var lastError: Error?
        
        while attempts < maxRetries {
            do {
                return try await operation()
            } catch {
                attempts += 1
                lastError = error
                
                if attempts < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts))) * 1_000_000_000)
                }
            }
        }
        
        throw handle(lastError ?? AppError.unknown(nil))
    }
    
    public func handleError(_ error: XcalpError) {
        logError(error)
        storeError(error)
        notifyObservers(error)
        
        if error.severity == .critical {
            handleCriticalError(error)
        }
    }
    
    public func observe(_ handler: @escaping (XcalpError) -> Void) {
        errorObservers.append(handler)
    }
    
    public func getRecentErrors() -> [XcalpError] {
        return recentErrors
    }
    
    // MARK: - Private Methods
    
    private func handleSecurityError(_ error: SecurityError) -> AppError {
        switch error {
        case .biometricUnavailable:
            return .security(.biometricsUnavailable)
        case .authenticationFailed:
            return .security(.authenticationFailed)
        case .encryptionFailed:
            return .security(.encryptionFailed)
        case .decryptionFailed:
            return .security(.decryptionFailed)
        }
    }
    
    private func handleNetworkError(_ error: NetworkError) -> AppError {
        switch error {
        case .invalidURL:
            return .network(.invalidRequest)
        case .invalidResponse:
            return .network(.invalidResponse)
        case .unauthorized:
            return .network(.unauthorized)
        case .serverError:
            return .network(.serverError)
        case .decodingError:
            return .network(.invalidData)
        case .noInternet:
            return .network(.noConnection)
        case .timeout:
            return .network(.timeout)
        case .unknown:
            return .network(.unknown)
        }
    }
    
    private func handleStorageError(_ error: SecureStorageService.StorageError) -> AppError {
        switch error {
        case .accessDenied:
            return .storage(.accessDenied)
        case .dataNotFound:
            return .storage(.notFound)
        case .encryptionFailed:
            return .storage(.encryptionFailed)
        case .decryptionFailed:
            return .storage(.decryptionFailed)
        }
    }
    
    private func handleMedicalError(_ error: HIPAAMedicalDataHandler.MedicalDataError) -> AppError {
        switch error {
        case .unauthorized:
            return .medical(.unauthorized)
        case .invalidData:
            return .medical(.invalidData)
        case .protectionFailed:
            return .medical(.protectionFailed)
        case .integrityCheckFailed:
            return .medical(.integrityFailed)
        }
    }
    
    private func logError(_ error: AppError, context: [String: Any]) {
        // Log to analytics
        analytics.logError(
            error,
            severity: error.severity,
            context: context
        )
        
        // Log to HIPAA audit if necessary
        if error.requiresHIPAALogging {
            logger.log(
                type: .systemError,
                action: error.logDescription,
                userID: SessionManager.shared.currentSession?.user.id ?? "UNKNOWN",
                details: context.description
            )
        }
    }
    
    private func logError(_ error: XcalpError) {
        switch error.severity {
        case .debug:
            logger.debug("\(error.localizedDescription)")
        case .info:
            logger.info("\(error.localizedDescription)")
        case .warning:
            logger.warning("\(error.localizedDescription)")
        case .error:
            logger.error("\(error.localizedDescription)")
        case .critical:
            logger.critical("\(error.localizedDescription)")
        }
    }
    
    private func storeError(_ error: XcalpError) {
        recentErrors.append(error)
        if recentErrors.count > maxStoredErrors {
            recentErrors.removeFirst()
        }
    }
    
    private func notifyObservers(_ error: XcalpError) {
        errorObservers.forEach { $0(error) }
    }
    
    private func handleCriticalError(_ error: XcalpError) {
        // Save current state
        StateManager.shared.saveCurrentState()
        
        // Post notification for UI update
        NotificationCenter.default.post(
            name: .criticalErrorOccurred,
            object: nil,
            userInfo: ["error": error]
        )
        
        // Report to analytics
        AnalyticsService.shared.trackError(error)
    }
}

// MARK: - Error Types

public enum AppError: LocalizedError {
    case security(SecurityErrorType)
    case network(NetworkErrorType)
    case storage(StorageErrorType)
    case medical(MedicalErrorType)
    case unknown(Error?)
    
    public var errorDescription: String? {
        switch self {
        case .security(let type):
            return type.localizedDescription
        case .network(let type):
            return type.localizedDescription
        case .storage(let type):
            return type.localizedDescription
        case .medical(let type):
            return type.localizedDescription
        case .unknown(let error):
            return error?.localizedDescription ?? "An unknown error occurred"
        }
    }
    
    public var severity: AnalyticsService.ErrorSeverity {
        switch self {
        case .security:
            return .critical
        case .medical:
            return .high
        case .network, .storage:
            return .medium
        case .unknown:
            return .low
        }
    }
    
    public var requiresHIPAALogging: Bool {
        switch self {
        case .security, .medical:
            return true
        case .network, .storage, .unknown:
            return false
        }
    }
    
    public var logDescription: String {
        switch self {
        case .security(let type):
            return "Security Error: \(type)"
        case .network(let type):
            return "Network Error: \(type)"
        case .storage(let type):
            return "Storage Error: \(type)"
        case .medical(let type):
            return "Medical Data Error: \(type)"
        case .unknown:
            return "Unknown Error"
        }
    }
    
    public enum SecurityErrorType: LocalizedError {
        case biometricsUnavailable
        case authenticationFailed
        case encryptionFailed
        case decryptionFailed
        
        public var errorDescription: String? {
            switch self {
            case .biometricsUnavailable:
                return NSLocalizedString("Biometric authentication is not available", comment: "")
            case .authenticationFailed:
                return NSLocalizedString("Authentication failed", comment: "")
            case .encryptionFailed:
                return NSLocalizedString("Failed to encrypt data", comment: "")
            case .decryptionFailed:
                return NSLocalizedString("Failed to decrypt data", comment: "")
            }
        }
    }
    
    public enum NetworkErrorType: LocalizedError {
        case invalidRequest
        case invalidResponse
        case unauthorized
        case serverError
        case invalidData
        case noConnection
        case timeout
        case unknown
        
        public var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return NSLocalizedString("Invalid request", comment: "")
            case .invalidResponse:
                return NSLocalizedString("Invalid response from server", comment: "")
            case .unauthorized:
                return NSLocalizedString("Unauthorized access", comment: "")
            case .serverError:
                return NSLocalizedString("Server error occurred", comment: "")
            case .invalidData:
                return NSLocalizedString("Invalid data received", comment: "")
            case .noConnection:
                return NSLocalizedString("No internet connection", comment: "")
            case .timeout:
                return NSLocalizedString("Request timed out", comment: "")
            case .unknown:
                return NSLocalizedString("Unknown network error", comment: "")
            }
        }
    }
    
    public enum StorageErrorType: LocalizedError {
        case accessDenied
        case notFound
        case encryptionFailed
        case decryptionFailed
        
        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return NSLocalizedString("Access denied", comment: "")
            case .notFound:
                return NSLocalizedString("Data not found", comment: "")
            case .encryptionFailed:
                return NSLocalizedString("Failed to encrypt data", comment: "")
            case .decryptionFailed:
                return NSLocalizedString("Failed to decrypt data", comment: "")
            }
        }
    }
    
    public enum MedicalErrorType: LocalizedError {
        case unauthorized
        case invalidData
        case protectionFailed
        case integrityFailed
        
        public var errorDescription: String? {
            switch self {
            case .unauthorized:
                return NSLocalizedString("Unauthorized access to medical data", comment: "")
            case .invalidData:
                return NSLocalizedString("Invalid medical data", comment: "")
            case .protectionFailed:
                return NSLocalizedString("Failed to protect medical data", comment: "")
            case .integrityFailed:
                return NSLocalizedString("Medical data integrity check failed", comment: "")
            }
        }
    }
}

public struct XcalpError: LocalizedError {
    public let id: UUID
    public let code: Int
    public let severity: Severity
    public let category: Category
    public let timestamp: Date
    public let underlyingError: Error?
    public let context: [String: Any]
    
    public var errorDescription: String? {
        return context["description"] as? String
    }
    
    public enum Severity {
        case debug
        case info
        case warning
        case error
        case critical
    }
    
    public enum Category {
        case network
        case scanning
        case processing
        case storage
        case security
        case validation
        case ui
        case unknown
    }
    
    public init(
        code: Int,
        severity: Severity,
        category: Category,
        description: String,
        underlyingError: Error? = nil,
        context: [String: Any] = [:]
    ) {
        self.id = UUID()
        self.code = code
        self.severity = severity
        self.category = category
        self.timestamp = Date()
        self.underlyingError = underlyingError
        var updatedContext = context
        updatedContext["description"] = description
        self.context = updatedContext
    }
}

extension Notification.Name {
    static let criticalErrorOccurred = Notification.Name("criticalErrorOccurred")
}
