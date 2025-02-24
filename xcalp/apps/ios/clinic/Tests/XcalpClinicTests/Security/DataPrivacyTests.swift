import ComposableArchitecture
@testable import XcalpClinic
import XCTest

final class DataPrivacyTests: XCTestCase {
    func testDataAnonymization() throws {
        let anonymizer = DataAnonymizer.shared
        
        // Test PII anonymization
        let patientData = PatientData(
            name: "John Doe",
            dob: "1990-01-01",
            ssn: "123-45-6789",
            address: "123 Main St"
        )
        
        let anonymized = try anonymizer.anonymize(patientData)
        XCTAssertNotEqual(anonymized.name, patientData.name)
        XCTAssertNotEqual(anonymized.ssn, patientData.ssn)
        XCTAssertTrue(anonymizer.isAnonymized(anonymized))
        
        // Test data restoration
        let restored = try anonymizer.deanonymize(anonymized)
        XCTAssertEqual(restored, patientData)
    }
    
    func testDataMinimization() throws {
        let minimizer = DataMinimizer.shared
        
        // Test data fields minimization
        let fullData = MedicalRecord(
            patientInfo: PatientData(name: "John Doe", dob: "1990-01-01", ssn: "123-45-6789", address: "123 Main St"),
            diagnosis: "Test Diagnosis",
            treatment: "Test Treatment",
            notes: "Confidential notes",
            billingInfo: "Payment details"
        )
        
        // Test minimization for different roles
        let doctorView = try minimizer.minimize(fullData, for: .doctor)
        XCTAssertNotNil(doctorView.diagnosis)
        XCTAssertNil(doctorView.billingInfo)
        
        let nurseView = try minimizer.minimize(fullData, for: .nurse)
        XCTAssertNotNil(nurseView.treatment)
        XCTAssertNil(nurseView.notes)
        
        let adminView = try minimizer.minimize(fullData, for: .admin)
        XCTAssertNotNil(adminView.billingInfo)
        XCTAssertNil(adminView.diagnosis)
    }
    
    func testDataRetention() async throws {
        let retention = DataRetentionManager.shared
        
        // Test data retention periods
        let retentionPeriods = retention.getRetentionPeriods()
        XCTAssertGreaterThanOrEqual(retentionPeriods[.medicalRecords] ?? 0, TimeInterval(7 * 365 * 24 * 60 * 60)) // 7 years
        
        // Test data archival
        let testData = "Test medical data".data(using: .utf8)!
        let identifier = try await retention.store(testData, type: .medicalRecords)
        
        // Simulate time passage
        let futureDate = Date().addingTimeInterval(retentionPeriods[.medicalRecords] ?? 0)
        try await retention.processRetention(currentDate: futureDate)
        
        // Verify data is archived
        XCTAssertTrue(try await retention.isArchived(identifier))
        
        // Test data deletion
        try await retention.delete(identifier)
        await XCTAssertThrowsError(try await retention.retrieve(identifier))
    }
    
    func testConsentManagement() async throws {
        let consent = ConsentManager.shared
        
        // Test consent recording
        let consentForm = ConsentForm(
            patientID: "test-patient",
            purpose: "Data Collection",
            dataTypes: ["Personal Info", "Medical History"],
            duration: TimeInterval(365 * 24 * 60 * 60) // 1 year
        )
        
        try await consent.recordConsent(consentForm)
        
        // Test consent validation
        XCTAssertTrue(try await consent.hasValidConsent(
            patientID: "test-patient",
            for: "Data Collection"
        ))
        
        // Test consent expiration
        let futureDate = Date().addingTimeInterval(consentForm.duration + 1)
        try await consent.validateConsents(currentDate: futureDate)
        XCTAssertFalse(try await consent.hasValidConsent(
            patientID: "test-patient",
            for: "Data Collection"
        ))
        
        // Test consent revocation
        try await consent.revokeConsent(
            patientID: "test-patient",
            purpose: "Data Collection"
        )
        XCTAssertFalse(try await consent.hasValidConsent(
            patientID: "test-patient",
            for: "Data Collection"
        ))
    }
    
    func testDataExport() async throws {
        let exporter = DataExportManager.shared
        
        // Test data export request
        let request = ExportRequest(
            patientID: "test-patient",
            dataTypes: ["Personal Info", "Medical History"],
            format: .json
        )
        
        let exportData = try await exporter.exportData(request)
        XCTAssertNotNil(exportData)
        
        // Test export format validation
        let json = try JSONSerialization.jsonObject(with: exportData, options: []) as? [String: Any]
        XCTAssertNotNil(json)
        
        // Test export logging
        let logs = try exporter.getExportLogs(for: "test-patient")
        XCTAssertTrue(logs.contains { $0.requestType == .patientRequest })
        
        // Test export rate limiting
        for _ in 1...exporter.maxExportsPerDay {
            _ = try await exporter.exportData(request)
        }
        await XCTAssertThrowsError(try await exporter.exportData(request))
    }
}
