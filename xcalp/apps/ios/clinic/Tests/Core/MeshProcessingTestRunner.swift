import Foundation
import Metal
import XCTest

@MainActor
final class MeshProcessingTestRunner {
    private let device: MTLDevice
    private let benchmarkSuite: MeshProcessingBenchmark
    private let stressTest: MeshProcessingStressTest
    private let testCoordinator: ScanningTestCoordinator
    private let resultsReporter: TestResultsReporter
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        
        // Initialize test components
        self.benchmarkSuite = MeshProcessingBenchmark(device: device)
        self.stressTest = MeshProcessingStressTest(device: device)
        self.testCoordinator = try ScanningTestCoordinator()
        self.resultsReporter = TestResultsReporter()
    }
    
    func runFullTestSuite() async throws -> TestSuiteResults {
        var results = TestSuiteResults()
        
        // Run standard validation tests
        print("Running validation tests...")
        results.validationResults = try await testCoordinator.runQualityValidationTests()
        
        // Run performance benchmarks
        print("Running performance benchmarks...")
        results.benchmarkReport = try await benchmarkSuite.runBenchmarkSuite()
        
        // Run stress tests
        print("Running stress tests...")
        results.stressTestResult = try await stressTest.runStressTest(
            config: .extreme
        )
        
        // Generate and save detailed report
        let report = resultsReporter.generateReport(
            performanceResults: results.getPerformanceReport(),
            concurrentResults: results.getConcurrencyResults(),
            meshQualities: results.getMeshQualities()
        )
        
        try resultsReporter.exportReport(
            report,
            to: getReportURL()
        )
        
        return results
    }
    
    func runQuickTests() async throws -> TestSuiteResults {
        var results = TestSuiteResults()
        
        // Run essential validation only
        results.validationResults = try await testCoordinator.runQualityValidationTests()
        
        // Run quick benchmark
        results.benchmarkReport = try await runQuickBenchmark()
        
        return results
    }
    
    private func runQuickBenchmark() async throws -> BenchmarkReport {
        // Run abbreviated benchmark suite
        let config = BenchmarkConfig(
            warmupRuns: 1,
            measurementRuns: 3,
            meshSizes: [1000, 10000],
            timeoutInterval: 10
        )
        
        return try await benchmarkSuite.runBenchmarkSuite()
    }
    
    private func getReportURL() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        
        return documentsPath.appendingPathComponent(
            "mesh_processing_test_report_\(timestamp).md"
        )
    }
}

struct TestSuiteResults {
    var validationResults: TestResult?
    var benchmarkReport: BenchmarkReport?
    var stressTestResult: MeshProcessingStressTest.StressTestResult?
    
    func getPerformanceReport() -> PerformanceReport {
        // Combine benchmark and stress test results
        let report = PerformanceReport()
        // Implementation needed
        return report
    }
    
    func getConcurrencyResults() -> ConcurrentTestResult {
        // Extract concurrency metrics
        let results = ConcurrentTestResult()
        // Implementation needed
        return results
    }
    
    func getMeshQualities() -> [String: QualityMetrics] {
        // Collect quality metrics from all tests
        var qualities: [String: QualityMetrics] = [:]
        // Implementation needed
        return qualities
    }
    
    var summary: String {
        return """
        Test Suite Results Summary:
        -------------------------
        Validation Tests: \(validationResults?.passed ?? false ? "✅" : "❌")
        Benchmark Tests: \(benchmarkReport != nil ? "✅" : "❌")
        Stress Tests: \(stressTestResult?.successRate ?? 0 > 0.9 ? "✅" : "❌")
        
        Performance Metrics:
        - Average Processing Time: \(benchmarkReport?.summary ?? "N/A")
        - Success Rate: \(String(format: "%.1f%%", (stressTestResult?.successRate ?? 0) * 100))
        """
    }
}