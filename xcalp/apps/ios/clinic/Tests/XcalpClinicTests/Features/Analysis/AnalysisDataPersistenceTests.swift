@testable import XcalpClinic
import XCTest

final class AnalysisDataPersistenceTests: XCTestCase {
    var dataManager: AnalysisDataManager!
    
    override func setUp() async throws {
        try await super.setUp()
        dataManager = AnalysisDataManager()
    }
    
    override func tearDown() async throws {
        try await dataManager.deleteAnalysisResults(type: .densityMapping)
        try await super.tearDown()
    }
    
    func testSaveAndLoadAnalysisResults() async throws {
        // Create test results
        let testResults = [
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: Date(),
                summary: "Test density: 45 follicles/cm²"
            )
        ]
        
        // Save results
        try await dataManager.saveAnalysisResults(testResults, type: .densityMapping)
        
        // Load results
        let loadedResults = try await dataManager.loadAnalysisResults(type: .densityMapping)
        
        // Verify data
        XCTAssertEqual(loadedResults.count, testResults.count)
        XCTAssertEqual(loadedResults[0].type, testResults[0].type)
        XCTAssertEqual(loadedResults[0].summary, testResults[0].summary)
    }
    
    func testHIPAACompliance() async throws {
        let hipaaLogger = HIPAALogger.shared
        let startEventCount = try hipaaLogger.exportLogs().count
        
        // Save test results
        let testResults = [
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: Date(),
                summary: "Test results"
            )
        ]
        try await dataManager.saveAnalysisResults(testResults, type: .densityMapping)
        
        // Verify HIPAA logging
        let logs = try hipaaLogger.exportLogs()
        XCTAssertEqual(logs.count, startEventCount + 1)
        
        let lastLog = logs.last!
        XCTAssertEqual(lastLog.type, .dataAccess)
        XCTAssertEqual(lastLog.resourceType, "analysis_results")
    }
    
    func testDataIntegrity() async throws {
        let testResults = [
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: Date(),
                summary: "Test integrity"
            )
        ]
        
        // Save results
        try await dataManager.saveAnalysisResults(testResults, type: .densityMapping)
        
        // Attempt to tamper with stored data
        let storageManager = SecureStorageManager.shared
        let pattern = "analysis_densityMapping_*"
        let keys = try await storageManager.listKeys(matching: pattern)
        let key = keys.sorted().last!
        
        // Load data
        let (originalData, metadata) = try await storageManager.load(key: key)
        
        // Create tampered data
        var tamperedData = originalData
        tamperedData[0] = tamperedData[0] ^ 0xFF // Flip bits
        
        // Try to verify tampered data
        let hipaaHandler = HIPAAMedicalDataHandler.shared
        let isValid = try hipaaHandler.verifyIntegrity(of: tamperedData, signature: metadata.signature)
        XCTAssertFalse(isValid)
    }
    
    func testConcurrentAccess() async throws {
        let concurrentAccess = 10
        let results = [
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: Date(),
                summary: "Concurrent test"
            )
        ]
        
        // Perform concurrent saves and loads
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentAccess {
                group.addTask {
                    if i % 2 == 0 {
                        try await self.dataManager.saveAnalysisResults(results, type: .densityMapping)
                    } else {
                        _ = try await self.dataManager.loadAnalysisResults(type: .densityMapping)
                    }
                }
            }
        }
        
        // Verify final state
        let finalResults = try await dataManager.loadAnalysisResults(type: .densityMapping)
        XCTAssertFalse(finalResults.isEmpty)
    }
    
    func testDataRetention() async throws {
        let hipaaHandler = HIPAAMedicalDataHandler.shared
        let retentionPeriod: TimeInterval = 90 * 24 * 60 * 60 // 90 days
        
        // Create old test results
        let oldDate = Date(timeIntervalSinceNow: -retentionPeriod - 86400) // Past retention + 1 day
        let oldResults = [
            AnalysisFeature.AnalysisResult(
                type: .densityMapping,
                date: oldDate,
                summary: "Old test"
            )
        ]
        
        try await dataManager.saveAnalysisResults(oldResults, type: .densityMapping)
        
        // Verify data is marked for deletion
        let shouldDelete = try hipaaHandler.validateRetention(
            date: oldDate,
            retentionPeriod: retentionPeriod
        )
        XCTAssertTrue(shouldDelete)
    }
}
