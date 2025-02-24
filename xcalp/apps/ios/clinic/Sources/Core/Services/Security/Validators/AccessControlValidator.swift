import Foundation

extension AccessControlCheck {
    func validate<T: HIPAACompliant>(_ data: T) async throws {
        // Get current user's access level
        let currentAccess = try await SessionManager.shared.getCurrentUserAccessLevel()
        
        // Verify user has sufficient access
        guard currentAccess.canAccess(data.accessControl) else {
            throw AccessError.insufficientPermissions(
                required: data.accessControl,
                current: currentAccess
            )
        }
        
        // Check for required audit trail
        try await verifyAuditTrail(for: data)
        
        // Verify access time restrictions
        try verifyAccessTimeRestrictions(for: data.accessControl)
        
        LoggingService.shared.logHIPAAEvent(
            "Access control validation successful",
            type: .access,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "requiredAccess": data.accessControl.rawValue,
                "userAccess": currentAccess.rawValue
            ]
        )
    }
    
    private func verifyAuditTrail<T: HIPAACompliant>(for data: T) async throws {
        let auditService = AuditService.shared
        
        // Ensure audit trail exists for sensitive data
        if data.accessControl == .restricted || data.accessControl == .confidential {
            let hasAuditTrail = try await auditService.hasAuditTrail(
                forIdentifier: data.identifier,
                type: T.dataType
            )
            
            guard hasAuditTrail else {
                throw AccessError.missingAuditTrail
            }
        }
    }
    
    private func verifyAccessTimeRestrictions(for level: AccessControlLevel) throws {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        
        // Restricted and confidential data can only be accessed during business hours
        if level == .restricted || level == .confidential {
            guard (9...17).contains(hour) else {
                throw AccessError.outsideBusinessHours
            }
        }
    }
}

enum AccessError: LocalizedError {
    case insufficientPermissions(required: AccessControlLevel, current: AccessControlLevel)
    case missingAuditTrail
    case outsideBusinessHours
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions(let required, let current):
            return "Insufficient permissions. Required: \(required), Current: \(current)"
        case .missingAuditTrail:
            return "Missing required audit trail for sensitive data"
        case .outsideBusinessHours:
            return "Access to sensitive data restricted to business hours (9 AM - 6 PM)"
        }
    }
}

extension AccessControlLevel {
    func canAccess(_ required: AccessControlLevel) -> Bool {
        switch self {
        case .public:
            return required == .public
        case .internal:
            return required != .restricted
        case .confidential:
            return true
        case .restricted:
            return true
        }
    }
}
