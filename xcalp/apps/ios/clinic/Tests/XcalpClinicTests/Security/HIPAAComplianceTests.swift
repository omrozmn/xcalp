import XCTest
import CryptoKit
@testable import XcalpClinicCore

final class HIPAAComplianceTests: XCTestCase {
    var complianceManager: HIPAAComplianceManager!
    var encryptionService: HIPAAEncryptionService!
    var auditService: RealAuditService!
    var keyRotation: KeyRotationManager!
    var emergencyAccess: EmergencyAccessManager!
    
    override func setUp() {
        super.setUp()
        complianceManager = HIPAAComplianceManager.shared
        encryptionService = HIPAAEncryptionService.shared
        auditService = RealAuditService.shared as? RealAuditService
        keyRotation = KeyRotationManager.shared
        emergencyAccess = EmergencyAccessManager.shared
    }
    
    // MARK: - Encryption Tests
    
    func testEncryptionKeyGeneration() throws {
        // Test key generation and storage
        let testData = "Sensitive PHI data".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(testData, type: .patientInfo)
        
        XCTAssertNotNil(encrypted)
        XCTAssertNotEqual(testData, encrypted.data)
        
        // Verify decryption works
        let decrypted = try encryptionService.decrypt(encrypted)
        XCTAssertEqual(testData, decrypted)
    }
    
    func testKeyRotation() async throws {
        // Test key rotation process
        let testData = "Test data for rotation".data(using: .utf8)!
        let encrypted = try encryptionService.encrypt(testData, type: .patientInfo)
        
        // Perform key rotation
        try await keyRotation.forceKeyRotation()
        
        // Verify data is still accessible after rotation
        let decrypted = try encryptionService.decrypt(encrypted)
        XCTAssertEqual(testData, decrypted)
    }
    
    // MARK: - Audit Trail Tests
    
    func testAuditTrailCreation() async throws {
        let resourceId = UUID().uuidString
        
        // Create audit entry
        try await auditService.addAuditEntry(
            resourceId: resourceId,
            resourceType: .patientInfo,
            action: .view,
            userId: "test-user",
            userRole: .doctor,
            accessReason: "Test access"
        )
        
        // Verify audit trail exists
        let hasTrail = try await auditService.hasAuditTrail(
            forIdentifier: resourceId,
            type: .patientInfo
        )
        XCTAssertTrue(hasTrail)
        
        // Verify audit content
        let trail = try await auditService.getAuditTrail(
            forIdentifier: resourceId,
            type: .patientInfo
        )
        XCTAssertFalse(trail.entries.isEmpty)
        XCTAssertEqual(trail.entries.first?.resourceId, resourceId)
    }
    
    // MARK: - Emergency Access Tests
    
    func testEmergencyAccess() async throws {
        // Request emergency access
        let token = try await emergencyAccess.requestEmergencyAccess(
            userId: "test-doctor",
            reason: .patientCritical,
            scope: .patientSpecific,
            duration: 3600 // 1 hour
        )
        
        // Validate token
        let access = try await emergencyAccess.validateEmergencyAccess(token)
        XCTAssertEqual(access.status, .active)
        XCTAssertEqual(access.userId, "test-doctor")
        
        // Revoke access
        try await emergencyAccess.revokeEmergencyAccess(
            accessId: access.id,
            revokedBy: "test-admin",
            reason: "Test complete"
        )
        
        // Verify access is revoked
        await XCTAssertThrowsError(try await emergencyAccess.validateEmergencyAccess(token))
    }
    
    // MARK: - PHI Validation Tests
    
    func testPHIValidation() async throws {
        let testPatient = TestPatient(
            id: UUID().uuidString,
            name: "encrypted:John Doe",
            ssn: "encrypted:123-45-6789",
            medicalRecord: "encrypted:12345",
            accessLevel: .confidential
        )
        
        // Test storing PHI data
        try await complianceManager.validateAndStore(testPatient)
        
        // Test retrieving PHI data
        let retrieved = try await complianceManager.retrieve(
            TestPatient.self,
            identifier: testPatient.id
        )
        XCTAssertEqual(retrieved.id, testPatient.id)
    }
    
    // MARK: - Helper Types
    
    private struct TestPatient: Codable, HIPAACompliant {
        static var dataType: DataType { .patientInfo }
        
        let id: String
        let name: String
        let ssn: String
        let medicalRecord: String
        let accessLevel: AccessControlLevel
        
        var identifier: String { id }
        var phi: [String : Any] {
            [
                "name": name,
                "ssn": ssn,
                "medicalRecord": medicalRecord
            ]
        }
        var lastModified: Date { Date() }
        var accessControl: AccessControlLevel { accessLevel }
    }
}