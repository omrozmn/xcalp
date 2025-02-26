import Foundation
import Combine

final class TestAlertHandler {
    static let shared = TestAlertHandler()
    private let alertSubject = PassthroughSubject<TestAlert, Never>()
    private var activeAlerts: Set<TestAlert> = []
    private var suppressedAlertTypes: Set<TestAlert.AlertType> = []
    
    enum AlertSeverity: Int, Comparable {
        case info = 0
        case warning = 1
        case error = 2
        case critical = 3
        
        static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    struct TestAlert: Hashable {
        let id: UUID
        let type: AlertType
        let severity: AlertSeverity
        let message: String
        let timestamp: Date
        let metadata: [String: String]
        
        enum AlertType: String {
            case performanceRegression
            case memoryPressure
            case qualityThresholdBreach
            case processingTimeout
            case deviceError
            case concurrencyIssue
            case recoveryFailure
            
            var defaultSeverity: AlertSeverity {
                switch self {
                case .performanceRegression: return .warning
                case .memoryPressure: return .warning
                case .qualityThresholdBreach: return .error
                case .processingTimeout: return .error
                case .deviceError: return .critical
                case .concurrencyIssue: return .error
                case .recoveryFailure: return .critical
                }
            }
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: TestAlert, rhs: TestAlert) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    var alertPublisher: AnyPublisher<TestAlert, Never> {
        return alertSubject.eraseToAnyPublisher()
    }
    
    func raiseAlert(
        type: TestAlert.AlertType,
        message: String,
        severity: AlertSeverity? = nil,
        metadata: [String: String] = [:]
    ) {
        guard !suppressedAlertTypes.contains(type) else { return }
        
        let alert = TestAlert(
            id: UUID(),
            type: type,
            severity: severity ?? type.defaultSeverity,
            message: message,
            timestamp: Date(),
            metadata: metadata
        )
        
        activeAlerts.insert(alert)
        alertSubject.send(alert)
        
        handleAlert(alert)
    }
    
    func clearAlert(_ alert: TestAlert) {
        activeAlerts.remove(alert)
    }
    
    func suppressAlertType(_ type: TestAlert.AlertType) {
        suppressedAlertTypes.insert(type)
    }
    
    func unsuppressAlertType(_ type: TestAlert.AlertType) {
        suppressedAlertTypes.remove(type)
    }
    
    private func handleAlert(_ alert: TestAlert) {
        switch alert.severity {
        case .critical:
            handleCriticalAlert(alert)
        case .error:
            handleErrorAlert(alert)
        case .warning:
            handleWarningAlert(alert)
        case .info:
            handleInfoAlert(alert)
        }
    }
    
    private func handleCriticalAlert(_ alert: TestAlert) {
        // Log critical alert
        logAlert(alert)
        
        // Notify test runner
        NotificationCenter.default.post(
            name: .testCriticalAlert,
            object: nil,
            userInfo: ["alert": alert]
        )
        
        // Consider test termination
        if shouldTerminateTests(for: alert) {
            terminateTests(reason: alert.message)
        }
    }
    
    private func handleErrorAlert(_ alert: TestAlert) {
        logAlert(alert)
        
        // Check for error patterns
        if shouldEscalateError(alert) {
            escalateToSeverity(.critical, for: alert)
        }
    }
    
    private func handleWarningAlert(_ alert: TestAlert) {
        logAlert(alert)
        
        // Check for warning patterns
        if isWarningPersistent(alert) {
            escalateToSeverity(.error, for: alert)
        }
    }
    
    private func handleInfoAlert(_ alert: TestAlert) {
        logAlert(alert)
    }
    
    private func logAlert(_ alert: TestAlert) {
        let logMessage = """
        [\(alert.severity)] \(alert.type.rawValue)
        Message: \(alert.message)
        Timestamp: \(alert.timestamp)
        Metadata: \(alert.metadata)
        """
        
        print(logMessage)
        // Additional logging implementation
    }
    
    private func shouldTerminateTests(for alert: TestAlert) -> Bool {
        // Implement termination decision logic
        return alert.severity == .critical && 
               activeAlerts.filter { $0.severity == .critical }.count >= 3
    }
    
    private func terminateTests(reason: String) {
        NotificationCenter.default.post(
            name: .testTermination,
            object: nil,
            userInfo: ["reason": reason]
        )
    }
    
    private func shouldEscalateError(_ alert: TestAlert) -> Bool {
        // Implement error escalation logic
        return activeAlerts.filter { 
            $0.type == alert.type && 
            $0.timestamp > Date().addingTimeInterval(-300) 
        }.count >= 5
    }
    
    private func isWarningPersistent(_ alert: TestAlert) -> Bool {
        // Implement warning persistence check
        return activeAlerts.filter {
            $0.type == alert.type &&
            $0.timestamp > Date().addingTimeInterval(-3600)
        }.count >= 10
    }
    
    private func escalateToSeverity(_ severity: AlertSeverity, for alert: TestAlert) {
        let escalatedAlert = TestAlert(
            id: UUID(),
            type: alert.type,
            severity: severity,
            message: "Escalated: \(alert.message)",
            timestamp: Date(),
            metadata: alert.metadata
        )
        
        raiseAlert(
            type: escalatedAlert.type,
            message: escalatedAlert.message,
            severity: escalatedAlert.severity,
            metadata: escalatedAlert.metadata
        )
    }
}

extension Notification.Name {
    static let testCriticalAlert = Notification.Name("testCriticalAlert")
    static let testTermination = Notification.Name("testTermination")
}