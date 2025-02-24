import Foundation

public enum XcalpError: LocalizedError {
    case security(SecurityError)
    case data(DataError)
    case network(NetworkError)
    case hipaa(HIPAAError)
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .security(let error): return error.localizedDescription
        case .data(let error): return error.localizedDescription
        case .network(let error): return error.localizedDescription
        case .hipaa(let error): return error.localizedDescription
        case .unknown(let error): return error.localizedDescription
        }
    }
}\n
// Security related errors
public enum SecurityError: LocalizedError {
    case keychainAccess(String)
    case authentication(String)
    case encryption(String)
    case invalidCredentials
    case sessionExpired
    case unauthorized
    
    public var errorDescription: String? {
        switch self {
        case .keychainAccess(let message): return "Keychain access error: \(message)"
        case .authentication(let message): return "Authentication error: \(message)"
        case .encryption(let message): return "Encryption error: \(message)"
        case .invalidCredentials: return "Invalid credentials provided"
        case .sessionExpired: return "Session has expired"
        case .unauthorized: return "Unauthorized access"
        }
    }
}

// Data handling errors
public enum DataError: LocalizedError {
    case invalidFormat(String)
    case corruption(String)
    case persistence(String)
    case validation(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let message): return "Invalid data format: \(message)"
        case .corruption(let message): return "Data corruption: \(message)"
        case .persistence(let message): return "Data persistence error: \(message)"
        case .validation(let message): return "Data validation error: \(message)"
        }
    }
}

// Network related errors
public enum NetworkError: LocalizedError {
    case connection(String)
    case timeout(String)
    case server(String)
    case client(String)
    
    public var errorDescription: String? {
        switch self {
        case .connection(let message): return "Connection error: \(message)"
        case .timeout(let message): return "Network timeout: \(message)"
        case .server(let message): return "Server error: \(message)"
        case .client(let message): return "Client error: \(message)"
        }
    }
}

// HIPAA compliance errors
public enum HIPAAError: LocalizedError {
    case complianceViolation(String)
    case dataProtection(String)
    case auditFailure(String)
    case unauthorized(String)
    
    public var errorDescription: String? {
        switch self {
        case .complianceViolation(let message): return "HIPAA compliance violation: \(message)"
        case .dataProtection(let message): return "Data protection error: \(message)"
        case .auditFailure(let message): return "Audit failure: \(message)"
        case .unauthorized(let message): return "Unauthorized access: \(message)"
        }
    }
}
