import XCTest
import ComposableArchitecture
@testable import XcalpClinic

final class AuditLogTests: XCTestCase {
    func testAuditLogCreation() throws {
        let logger = HIPAALogger.shared
        
        // Test basic logging
        logger.log(
            type: .dataAccess,
            action: "View Patient Data",
            userID: "test-doctor",
            details: "Accessed patient record 123"
        )
        
        // Verify log entry
        let logs = try logger.exportLogs()
        XCTAssertTrue(logs.contains { event in
            event.type == .dataAccess &&
            event.userID == "test-doctor" &&
            event.details.contains("patient record 123")
        })
    }
    
    func testAuditLogIntegrity() throws {
        let logger = HIPAALogger.shared
        let verifier = AuditLogVerifier.shared
        
        // Create test logs
        logger.log(
            type: .authentication,
            action: "Login",
            userID: "test-user",
            details: "User login successful"
        )
        
        // Export and verify logs
        let logs = try logger.exportLogs()
        XCTAssertTrue(try verifier.verifyLogIntegrity(logs))
        
        // Test tampering detection
        var tamperedLogs = logs
        tamperedLogs[0].timestamp = Date()
        XCTAssertFalse(try verifier.verifyLogIntegrity(tamperedLogs))
    }
    
    func testAuditLogRetention() async throws {
        let logger = HIPAALogger.shared
        
        // Test log retention period
        let retentionPeriod = try XCTUnwrap(logger.logRetentionPeriod)
        XCTAssertGreaterThanOrEqual(retentionPeriod, TimeInterval(6 * 30 * 24 * 60 * 60)) // 6 months minimum
        
        // Create old log entry
        let oldDate = Date().addingTimeInterval(-retentionPeriod - 86400) // One day past retention
        logger.log(
            type: .systemEvent,
            action: "Old Event",
            userID: "test-user",
            details: "This should be archived",
            timestamp: oldDate
        )
        
        // Trigger archival process
        try await logger.performLogMaintenance()
        
        // Verify current logs don't contain old entry
        let currentLogs = try logger.exportLogs()
        XCTAssertFalse(currentLogs.contains { $0.timestamp <= oldDate })
        
        // Verify archived logs contain old entry
        let archivedLogs = try logger.exportArchivedLogs()
        XCTAssertTrue(archivedLogs.contains { $0.timestamp <= oldDate })
    }
    
    func testAuditLogExport() async throws {
        let logger = HIPAALogger.shared
        let exporter = AuditLogExporter.shared
        
        // Create test logs
        for i in 1...5 {
            logger.log(
                type: .dataAccess,
                action: "Test Action \(i)",
                userID: "test-user",
                details: "Test details \(i)"
            )
        }
        
        // Test JSON export
        let jsonData = try await exporter.exportAsJSON()
        let jsonLogs = try JSONDecoder().decode([AuditEvent].self, from: jsonData)
        XCTAssertGreaterThanOrEqual(jsonLogs.count, 5)
        
        // Test CSV export
        let csvData = try await exporter.exportAsCSV()
        let csvString = String(data: csvData, encoding: .utf8)
        XCTAssertNotNil(csvString)
        XCTAssertTrue(csvString?.contains("test-user") ?? false)
        
        // Test encrypted export
        let encryptedData = try await exporter.exportEncrypted(password: "test-password")
        let decryptedData = try await exporter.decryptExport(encryptedData, password: "test-password")
        let decryptedLogs = try JSONDecoder().decode([AuditEvent].self, from: decryptedData)
        XCTAssertGreaterThanOrEqual(decryptedLogs.count, 5)
    }
    
    func testAuditLogSearch() async throws {
        let logger = HIPAALogger.shared
        let searcher = AuditLogSearcher.shared
        
        // Create test logs with various events
        logger.log(
            type: .dataAccess,
            action: "View Patient Data",
            userID: "doctor-1",
            details: "Accessed patient 123"
        )
        
        logger.log(
            type: .authentication,
            action: "Login",
            userID: "nurse-1",
            details: "Nurse login"
        )
        
        logger.log(
            type: .dataAccess,
            action: "Edit Treatment Plan",
            userID: "doctor-1",
            details: "Modified treatment for patient 123"
        )
        
        // Test search by user
        let userLogs = try await searcher.search(userID: "doctor-1")
        XCTAssertEqual(userLogs.count, 2)
        
        // Test search by date range
        let dateRange = DateInterval(
            start: Date().addingTimeInterval(-3600),
            duration: 3600
        )
        let dateLogs = try await searcher.search(dateRange: dateRange)
        XCTAssertGreaterThanOrEqual(dateLogs.count, 3)
        
        // Test search by event type
        let accessLogs = try await searcher.search(type: .dataAccess)
        XCTAssertEqual(accessLogs.count, 2)
        
        // Test complex search
        let complexLogs = try await searcher.search(
            userID: "doctor-1",
            type: .dataAccess,
            dateRange: dateRange,
            details: "patient 123"
        )
        XCTAssertEqual(complexLogs.count, 2)
    }
}
