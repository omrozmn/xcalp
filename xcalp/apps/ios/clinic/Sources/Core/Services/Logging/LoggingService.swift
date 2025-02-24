import FirebaseCrashlytics
import Foundation
import os.log

public final class LoggingService {
    public static let shared = LoggingService()
    
    private let hipaaLogger = Logger(subsystem: "com.xcalp.clinic", category: "HIPAA")
    private let securityLogger = Logger(subsystem: "com.xcalp.clinic", category: "Security")
    private let performanceLogger = Logger(subsystem: "com.xcalp.clinic", category: "Performance")
    private let networkLogger = Logger(subsystem: "com.xcalp.clinic", category: "Network")
    
    private init() {}
    
    public func logHIPAAEvent(_ message: String, type: HIPAAEventType, metadata: [String: Any]? = nil) {
        let logMessage = formatHIPAAMessage(message, type: type, metadata: metadata)
        hipaaLogger.log(level: type.osLogType, "\(logMessage)")
        
        // Record in Crashlytics for aggregation
        Crashlytics.crashlytics().record(error: NSError(
            domain: "HIPAA",
            code: type.rawValue,
            userInfo: ["message": message, "metadata": metadata ?? [:]]
        ))
    }
    
    public func logSecurityEvent(_ message: String, level: SecurityLevel, metadata: [String: Any]? = nil) {
        let logMessage = formatSecurityMessage(message, level: level, metadata: metadata)
        securityLogger.log(level: level.osLogType, "\(logMessage)")
    }
    
    public func logPerformanceMetric(_ metric: PerformanceMetric) {
        performanceLogger.log(level: .info, "\(metric.description)")
        Crashlytics.crashlytics().setCustomValue(metric.value, forKey: metric.name)
    }
    
    public func logNetworkEvent(_ event: NetworkEvent) {
        networkLogger.log(level: event.level.osLogType, "\(event.description)")
    }
    
    private func formatHIPAAMessage(_ message: String, type: HIPAAEventType, metadata: [String: Any]?) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataStr = metadata.map { String(describing: $0) } ?? "none"
        return "[\(timestamp)] [\(type)] \(message) - Metadata: \(metadataStr)"
    }
    
    private func formatSecurityMessage(_ message: String, level: SecurityLevel, metadata: [String: Any]?) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataStr = metadata.map { String(describing: $0) } ?? "none"
        return "[\(timestamp)] [\(level)] \(message) - Metadata: \(metadataStr)"
    }
}

public enum HIPAAEventType: Int {
    case access = 1
    case modification
    case transmission
    case deletion
    case export
    case authentication
    
    var osLogType: OSLogType {
        switch self {
        case .access, .modification, .transmission:
            return .info
        case .deletion, .export:
            return .debug
        case .authentication:
            return .default
        }
    }
}

public enum SecurityLevel: Int {
    case info
    case warning
    case error
    case critical
    
    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .warning: return .debug
        case .error: return .error
        case .critical: return .fault
        }
    }
}

public struct PerformanceMetric {
    let name: String
    let value: Double
    let unit: String
    let timestamp: Date
    
    var description: String {
        "[\(name)] \(value)\(unit) at \(timestamp)"
    }
}

public struct NetworkEvent {
    let type: NetworkEventType
    let url: URL
    let statusCode: Int?
    let error: Error?
    let duration: TimeInterval
    let timestamp: Date
    
    var level: SecurityLevel {
        switch statusCode {
        case .none, 500...: return .error
        case 400...499: return .warning
        default: return .info
        }
    }
    
    var description: String {
        let status = statusCode.map { String($0) } ?? "unknown"
        return "[\(type)] \(url) - Status: \(status), Duration: \(duration)s"
    }
}

public enum NetworkEventType {
    case request
    case response
    case error
}
