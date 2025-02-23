import Foundation
import Dependencies

/// Core services manifest for XcalpClinic
enum CoreServices {
    // MARK: - Security Services
    static let hipaaCompliance = HIPAAComplianceManager.shared
    static let encryption = HIPAAEncryptionService.shared
    static let auditService = RealAuditService.shared
    static let keyRotation = KeyRotationManager.shared
    static let emergencyAccess = EmergencyAccessManager.shared
    static let securityMetrics = SecurityMetricsDashboard.shared
    static let anonymizer = DataAnonymizer.shared
    
    // MARK: - Storage Services
    static let secureStorage = SecureStorageService.shared
    
    // MARK: - Logging Services
    static let logging = LoggingService.shared
    
    // MARK: - Monitoring Services
    static let auditAnalyzer = AuditAnalyzer.shared
    
    // MARK: - Reporting Services
    static let complianceReporter = ComplianceReportGenerator.shared
}

// MARK: - Dependencies Registration

private enum CoreServicesKey: DependencyKey {
    static let liveValue = CoreServices.self
    
    #if DEBUG
    static let testValue = CoreServices.self // In real implementation, would use mock services
    #endif
}

extension DependencyValues {
    var coreServices: CoreServices.Type {
        get { self[CoreServicesKey.self] }
        set { self[CoreServicesKey.self] = newValue }
    }
}