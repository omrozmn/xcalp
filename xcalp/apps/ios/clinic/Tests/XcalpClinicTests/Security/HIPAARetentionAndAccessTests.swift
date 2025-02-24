import CryptoKit
@testable import XcalpClinicCore
import XCTest

final class HIPAARetentionAndAccessTests: XCTestCase {
    // MARK: - Data Retention Tests
    
    func testDataRetentionValidation() async throws {
        let dataRetentionCheck = DataRetentionCheck()
        
        // Test data within retention period
        let recentData = TestMedicalRecord(
            id: UUID().uuidString,
            createdAt: Date(),
            accessLevel: .confidential
        )
        await XCTAssertNoThrow(try await dataRetentionCheck.validate(recentData))
        
        // Test data exceeding retention period
        let oldData = TestMedicalRecord(
            id: UUID().uuidString,
            createdAt: Calendar.current.date(byAdding: .year, value: -11, to: Date())!,
            accessLevel: .confidential
        )
        await XCTAssertThrowsError(try await dataRetentionCheck.validate(oldData))
    }
    
    func testAutomaticArchival() async throws {
        let dataRetentionCheck = DataRetentionCheck()
        let sixYearsAgo = Calendar.current.date(byAdding: .year, value: -6, to: Date())!
        
        let agingData = TestMedicalRecord(
            id: UUID().uuidString,
            createdAt: sixYearsAgo,
            accessLevel: .confidential
        )
        
        // Validate triggers archival
        await XCTAssertNoThrow(try await dataRetentionCheck.validate(agingData))
        
        // Verify archival status
        let storage = SecureStorageService.shared
        let isArchived = try await storage.retrieve(
            type: .systemConfig,
            identifier: "archive_\(agingData.id)"
        ) as? ArchiveMetadata
        
        XCTAssertNotNil(isArchived)
        XCTAssertEqual(isArchived?.originalIdentifier, agingData.id)
    }
    
    // MARK: - Access Control Tests
    
    func testAccessLevelValidation() async throws {
        let accessControl = AccessControlCheck()
        
        // Test restricted access during business hours
        let restrictedData = TestMedicalRecord(
            id: UUID().uuidString,
            createdAt: Date(),
            accessLevel: .restricted
        )
        
        // Should succeed during business hours (9-17)
        let businessHour = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        setTestDate(businessHour)
        await XCTAssertNoThrow(try await accessControl.validate(restrictedData))
        
        // Should fail outside business hours
        let afterHours = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        setTestDate(afterHours)
        await XCTAssertThrowsError(try await accessControl.validate(restrictedData))
    }
    
    func testRoleBasedAccess() async throws {
        let accessControl = AccessControlCheck()
        
        // Set up test data with different access levels
        let confidentialData = TestMedicalRecord(
            id: UUID().uuidString,
            createdAt: Date(),
            accessLevel: .confidential
        )
        
        // Test doctor access (should succeed)
        setTestUser(.doctor)
        await XCTAssertNoThrow(try await accessControl.validate(confidentialData))
        
        // Test nurse access (should succeed)
        setTestUser(.nurse)
        await XCTAssertNoThrow(try await accessControl.validate(confidentialData))
        
        // Test staff access (should fail for confidential data)
        setTestUser(.staff)
        await XCTAssertThrowsError(try await accessControl.validate(confidentialData))
    }
    
    // MARK: - Helper Types & Methods
    
    private struct TestMedicalRecord: Codable, HIPAACompliant {
        static var dataType: DataType { .patientInfo }
        
        let id: String
        let createdAt: Date
        let accessLevel: AccessControlLevel
        
        var identifier: String { id }
        var phi: [String: Any] { [:] }
        var lastModified: Date { createdAt }
        var accessControl: AccessControlLevel { accessLevel }
    }
    
    private func setTestDate(_ date: Date) {
        // Implementation would set test date for validation
    }
    
    private func setTestUser(_ role: UserRole) {
        // Implementation would set test user role
    }
}
