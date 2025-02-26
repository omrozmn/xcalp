import XCTest
@testable import xcalp

final class ScanningValidationTests: XCTestCase {
    private var coordinator: ScanningTestCoordinator!
    
    override func setUp() async throws {
        coordinator = try ScanningTestCoordinator()
    }
    
    override func tearDown() {
        coordinator = nil
    }
    
    func testMeshProcessingQuality() async throws {
        let results = try await coordinator.runQualityValidationTests()
        XCTAssertTrue(results.allPassed, results.summary)
    }
    
    func testProcessingPerformance() async throws {
        let results = try await coordinator.runPerformanceTests()
        XCTAssertTrue(results.allPassed, results.summary)
    }
    
    func testErrorRecovery() async throws {
        // Test recovery from common scanning errors
        let result = try await coordinator.testErrorRecovery()
        XCTAssertTrue(result.passed, "Error recovery test failed")
    }
    
    func testConcurrentOperations() async throws {
        // Test handling multiple scanning operations
        let result = try await coordinator.testConcurrentOperations()
        XCTAssertTrue(result.passed, "Concurrent operations test failed")
    }
    
    func testQualityAnalysis() async throws {
        // Test quality metrics calculation
        let result = try await coordinator.testQualityAnalysis()
        XCTAssertTrue(result.passed, "Quality analysis test failed")
    }
    
    func testMemoryUsage() async throws {
        // Test memory management during scanning
        let result = try await coordinator.testMemoryUsage()
        XCTAssertTrue(result.passed, "Memory usage test failed")
        XCTAssertLessThan(
            result.measurements["peak_memory_mb"] ?? .infinity,
            Float(TestConfiguration.maxMemoryUsage) / (1024 * 1024),
            "Memory usage exceeds limit"
        )
    }
    
    func testProcessingTimeLimit() async throws {
        // Test processing time constraints
        let result = try await coordinator.testProcessingPerformance()
        XCTAssertTrue(result.passed, "Processing time test failed")
        XCTAssertLessThan(
            result.measurements["average_processing_time"] ?? .infinity,
            Float(TestConfiguration.maxProcessingTime),
            "Processing time exceeds limit"
        )
    }
}

// Helper Extensions
extension XCTestCase {
    func XCTAssertQualityThreshold(_ value: Float,
                                  threshold: Float,
                                  message: String) {
        XCTAssertGreaterThanOrEqual(
            value,
            threshold,
            "\(message): \(value) below threshold \(threshold)"
        )
    }
    
    func XCTAssertPerformanceThreshold(_ value: Float,
                                      maximum: Float,
                                      message: String) {
        XCTAssertLessThanOrEqual(
            value,
            maximum,
            "\(message): \(value) exceeds maximum \(maximum)"
        )
    }
}