import Foundation

public final class AccessControlService {
    public static let shared = AccessControlService()
    
    private let queue = DispatchQueue(label: "com.xcalp.clinic.access", qos: .userInitiated)
    private var permissionCache: [UserRole: Set<Permission>] = [:]
    
    private init() {
        setupDefaultPermissions()
    }
    
    /// Get permissions for a specific role
    /// - Parameter role: User role to get permissions for
    /// - Returns: Set of permissions for the role
    public func getPermissions(for role: UserRole) -> Set<Permission> {
        queue.sync { permissionCache[role] ?? [] }
    }
    
    /// Check if a role has a specific permission
    /// - Parameters:
    ///   - permission: Permission to check
    ///   - role: Role to check permission for
    /// - Returns: Whether the role has the permission
    public func hasPermission(_ permission: Permission, role: UserRole) -> Bool {
        queue.sync { permissionCache[role]?.contains(permission) ?? false }
    }
    
    /// Validate access for current user
    /// - Parameter permission: Permission to validate
    /// - Returns: Whether access is granted
    public func validateAccess(for permission: Permission) -> Bool {
        guard let session = AuthenticationService.shared.currentSession else {
            return false
        }
        
        let hasPermission = hasPermission(permission, role: session.role)
        
        // Log access attempt
        HIPAALogger.shared.log(
            type: .access,
            action: hasPermission ? "access_granted" : "access_denied",
            userID: session.userID,
            details: "Permission: \(permission.rawValue)"
        )
        
        return hasPermission
    }
    
    /// Grant emergency access to a user
    /// - Parameters:
    ///   - userID: User to grant emergency access to
    ///   - reason: Reason for emergency access
    /// - Returns: Whether emergency access was granted
    public func grantEmergencyAccess(userID: String, reason: String) async throws -> Bool {
        // Verify current user has permission to grant emergency access
        guard validateAccess(for: .grantEmergencyAccess) else {
            throw AccessControlError.unauthorizedAccess
        }
        
        // Log emergency access grant
        HIPAALogger.shared.log(
            type: .emergency,
            action: "emergency_access_granted",
            userID: userID,
            details: "Reason: \(reason)"
        )
        
        // TODO: Implement emergency access time limit and automatic revocation
        return true
    }
    
    /// Revoke emergency access from a user
    /// - Parameter userID: User to revoke emergency access from
    public func revokeEmergencyAccess(userID: String) async throws {
        // Verify current user has permission to revoke emergency access
        guard validateAccess(for: .grantEmergencyAccess) else {
            throw AccessControlError.unauthorizedAccess
        }
        
        // Log emergency access revocation
        HIPAALogger.shared.log(
            type: .emergency,
            action: "emergency_access_revoked",
            userID: userID
        )
    }
    
    private func setupDefaultPermissions() {
        queue.sync {
            // Admin permissions
            permissionCache[.admin] = Set(Permission.allCases)
            
            // Doctor permissions
            permissionCache[.doctor] = [
                .viewPatientData,
                .editPatientData,
                .performScans,
                .createTreatmentPlan,
                .editTreatmentPlan,
                .viewAnalytics,
                .exportData
            ]
            
            // Nurse permissions
            permissionCache[.nurse] = [
                .viewPatientData,
                .editPatientData,
                .performScans,
                .viewTreatmentPlan
            ]
            
            // Patient permissions
            permissionCache[.patient] = [
                .viewOwnData,
                .exportOwnData
            ]
        }
    }
}

public enum Permission: String, CaseIterable {
    // Patient data permissions
    case viewPatientData = "view_patient_data"
    case editPatientData = "edit_patient_data"
    case viewOwnData = "view_own_data"
    case exportOwnData = "export_own_data"
    
    // Treatment permissions
    case performScans = "perform_scans"
    case createTreatmentPlan = "create_treatment_plan"
    case editTreatmentPlan = "edit_treatment_plan"
    case viewTreatmentPlan = "view_treatment_plan"
    
    // Administrative permissions
    case manageUsers = "manage_users"
    case manageRoles = "manage_roles"
    case viewAnalytics = "view_analytics"
    case exportData = "export_data"
    case grantEmergencyAccess = "grant_emergency_access"
}

public enum AccessControlError: LocalizedError {
    case unauthorizedAccess
    case invalidRole
    case invalidPermission
    
    public var errorDescription: String? {
        switch self {
        case .unauthorizedAccess:
            return "Unauthorized access attempt"
        case .invalidRole:
            return "Invalid user role"
        case .invalidPermission:
            return "Invalid permission"
        }
    }
}
