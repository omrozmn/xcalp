import Foundation
import CoreLocation
import LocalAuthentication
import Network

public actor SecurityMonitor {
    public static let shared = SecurityMonitor()
    
    private let hipaaLogger: HIPAALogger
    private let analytics: AnalyticsService
    private let networkMonitor = NWPathMonitor()
    private var locationManager: CLLocationManager?
    private var securityViolations: [SecurityViolation] = []
    private let violationThreshold = 3
    private let reviewPeriod: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private init(
        hipaaLogger: HIPAALogger = .shared,
        analytics: AnalyticsService = .shared
    ) {
        self.hipaaLogger = hipaaLogger
        self.analytics = analytics
        setupMonitoring()
    }
    
    public func analyzeEvent(_ event: HIPAALogger.LogEntry) async {
        // Check for potential security violations
        if let violation = detectViolation(from: event) {
            await handleViolation(violation)
        }
        
        // Analyze patterns
        await analyzePatterns()
        
        // Clean up old violations
        cleanupOldViolations()
    }
    
    private func detectViolation(from event: HIPAALogger.LogEntry) -> SecurityViolation? {
        // Check for unusual access patterns
        if event.event.name.contains("authentication") {
            if let attempts = event.details["attempts"] as? Int, attempts > 3 {
                return SecurityViolation(
                    type: .multipleFailedLogins,
                    severity: .high,
                    event: event
                )
            }
        }
        
        // Check for unauthorized data access
        if event.event.name.contains("data_access") {
            if event.details["authorized"] as? Bool == false {
                return SecurityViolation(
                    type: .unauthorizedAccess,
                    severity: .critical,
                    event: event
                )
            }
        }
        
        // Check for unusual locations
        if let location = event.details["location"] as? CLLocation {
            if !isLocationAuthorized(location) {
                return SecurityViolation(
                    type: .unusualLocation,
                    severity: .high,
                    event: event
                )
            }
        }
        
        // Check for data export violations
        if event.event.name.contains("data_export") {
            if !isExportAuthorized(event) {
                return SecurityViolation(
                    type: .unauthorizedExport,
                    severity: .critical,
                    event: event
                )
            }
        }
        
        return nil
    }
    
    private func handleViolation(_ violation: SecurityViolation) async {
        // Log violation
        await hipaaLogger.log(
            event: .securityViolation,
            details: [
                "type": violation.type.rawValue,
                "severity": violation.severity.rawValue,
                "timestamp": Date(),
                "originalEvent": violation.event
            ]
        )
        
        // Track for pattern analysis
        securityViolations.append(violation)
        
        // Handle based on severity
        switch violation.severity {
        case .critical:
            await handleCriticalViolation(violation)
        case .high:
            await handleHighSeverityViolation(violation)
        case .medium:
            await handleMediumSeverityViolation(violation)
        case .low:
            await handleLowSeverityViolation(violation)
        }
        
        // Notify analytics
        analytics.track(
            event: .securityViolationDetected,
            properties: [
                "type": violation.type.rawValue,
                "severity": violation.severity.rawValue
            ]
        )
    }
    
    private func handleCriticalViolation(_ violation: SecurityViolation) async {
        // Force logout
        await SessionManager.shared.logout()
        
        // Lock affected resources
        await lockCompromisedResources(violation)
        
        // Notify security team
        NotificationCenter.default.post(
            name: .criticalSecurityViolation,
            object: nil,
            userInfo: ["violation": violation]
        )
    }
    
    private func handleHighSeverityViolation(_ violation: SecurityViolation) async {
        // Require additional authentication
        await requireStepUpAuthentication()
        
        // Log detailed audit
        await createDetailedAuditLog(violation)
    }
    
    private func handleMediumSeverityViolation(_ violation: SecurityViolation) async {
        // Increase monitoring
        intensifyMonitoring()
        
        // Update risk score
        await updateUserRiskScore(violation)
    }
    
    private func handleLowSeverityViolation(_ violation: SecurityViolation) async {
        // Log for pattern analysis
        await logForPatternAnalysis(violation)
    }
    
    private func analyzePatterns() async {
        let recentViolations = securityViolations.filter {
            $0.timestamp.timeIntervalSinceNow > -reviewPeriod
        }
        
        // Check for pattern-based threats
        if let pattern = detectThreatPattern(in: recentViolations) {
            await handleThreatPattern(pattern)
        }
    }
    
    private func setupMonitoring() {
        // Setup network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.validateNetworkSecurity(path)
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
        
        // Setup location monitoring if authorized
        locationManager = CLLocationManager()
        locationManager?.allowsBackgroundLocationUpdates = false
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    private func cleanupOldViolations() {
        securityViolations.removeAll {
            $0.timestamp.timeIntervalSinceNow < -reviewPeriod
        }
    }
}

// MARK: - Types

extension SecurityMonitor {
    struct SecurityViolation {
        let id: UUID = UUID()
        let type: ViolationType
        let severity: Severity
        let timestamp: Date = Date()
        let event: HIPAALogger.LogEntry
        
        enum ViolationType: String {
            case multipleFailedLogins = "multiple_failed_logins"
            case unauthorizedAccess = "unauthorized_access"
            case unusualLocation = "unusual_location"
            case unauthorizedExport = "unauthorized_export"
            case suspiciousActivity = "suspicious_activity"
        }
        
        enum Severity: String {
            case critical
            case high
            case medium
            case low
        }
    }
    
    struct ThreatPattern {
        let violations: [SecurityViolation]
        let patternType: PatternType
        let riskLevel: RiskLevel
        
        enum PatternType {
            case bruteForceAttempt
            case systematicDataAccess
            case coordinatedAttack
            case abnormalUsage
        }
        
        enum RiskLevel {
            case extreme
            case high
            case moderate
            case low
        }
    }
}

extension HIPAALogger.Event {
    static let securityViolation = HIPAALogger.Event(
        name: "security_violation",
        isSecuritySensitive: true
    )
}

extension AnalyticsService.Event {
    static let securityViolationDetected = AnalyticsService.Event(name: "security_violation_detected")
}

extension Notification.Name {
    static let criticalSecurityViolation = Notification.Name("criticalSecurityViolation")
}