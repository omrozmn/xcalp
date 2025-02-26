import XCTest
@testable import XCalp

class ClinicalIntegrationTests: XCTestCase {
    var clinicalAnalysis: ClinicalAnalysis!
    var testDataManager: TestDataManager!
    
    override func setUp() {
        super.setUp()
        clinicalAnalysis = .shared
        testDataManager = TestDataManager()
    }
    
    override func tearDown() {
        clinicalAnalysis = nil
        testDataManager = nil
        super.tearDown()
    }
    
    func testEndToEndAnalysis() async throws {
        // Test complete analysis pipeline with various scan types
        let scanTypes = ["normal", "sparse", "dense", "irregular"]
        
        for scanType in scanTypes {
            let scanData = try testDataManager.loadTestScan(type: scanType)
            
            // Perform full analysis
            let result = try await clinicalAnalysis.analyzeScan(scanData)
            
            // Verify each component's output
            XCTAssertNotNil(result.surfaceData)
            XCTAssertNotNil(result.densityAnalysis)
            XCTAssertFalse(result.recommendations.isEmpty)
            
            // Verify quality metrics
            XCTAssertGreaterThan(result.quality.coverage, 0.9)
            XCTAssertGreaterThan(result.quality.resolution, 500)
            XCTAssertGreaterThan(result.quality.confidence, 0.8)
        }
    }
    
    func testComponentInteractions() async throws {
        let scanData = try testDataManager.loadTestScan(type: "normal")
        
        // Test sequential processing
        // 1. Quality validation
        let qualityResult = try await clinicalAnalysis.validateScanQuality(scanData)
        XCTAssertTrue(qualityResult)
        
        // 2. Surface analysis
        let surfaceAnalyzer = try SurfaceAnalyzer()
        let surfaceData = try await surfaceAnalyzer.analyzeSurface(scanData)
        XCTAssertFalse(surfaceData.regions.isEmpty)
        
        // 3. Density analysis
        let densityAnalysis = try await clinicalAnalysis.analyzeDensity(scanData)
        XCTAssertGreaterThan(densityAnalysis.averageDensity, 0)
        
        // 4. Graft planning
        let graftPlan = try await clinicalAnalysis.calculateGraftPlan(
            scanData: scanData,
            targetDensity: 65.0
        )
        XCTAssertEqual(graftPlan.directions.count, graftPlan.totalGrafts)
    }
    
    func testConcurrentProcessing() async throws {
        let scanData = try testDataManager.loadTestScan(type: "normal")
        
        // Test parallel processing capabilities
        async let qualityTask = clinicalAnalysis.validateScanQuality(scanData)
        async let surfaceTask = try SurfaceAnalyzer().analyzeSurface(scanData)
        
        let (isValid, surfaceData) = try await (qualityTask, surfaceTask)
        
        XCTAssertTrue(isValid)
        XCTAssertFalse(surfaceData.regions.isEmpty)
    }
    
    func testPerformanceBaseline() async throws {
        let scanSizes = ["small", "medium", "large"]
        
        for size in scanSizes {
            let scanData = try testDataManager.loadTestScan(type: size)
            
            let startTime = DispatchTime.now()
            let _ = try await clinicalAnalysis.analyzeScan(scanData)
            let endTime = DispatchTime.now()
            
            let timeInterval = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            
            // Log performance metrics
            print("Analysis time for \(size) scan: \(timeInterval) seconds")
            
            // Verify performance thresholds
            switch size {
            case "small":
                XCTAssertLessThan(timeInterval, 2.0)
            case "medium":
                XCTAssertLessThan(timeInterval, 5.0)
            case "large":
                XCTAssertLessThan(timeInterval, 10.0)
            default:
                break
            }
        }
    }
    
    func testMemoryEfficiency() async throws {
        let scanData = try testDataManager.loadTestScan(type: "large")
        
        // Track memory usage during analysis
        var memoryMetrics: [String: (start: Int64, peak: Int64, end: Int64)] = [:]
        
        // Test individual components
        let components = [
            "surfaceAnalysis",
            "densityAnalysis",
            "graftPlanning"
        ]
        
        for component in components {
            let startMemory = reportMemoryUsage()
            var peakMemory = startMemory
            
            // Perform component analysis
            switch component {
            case "surfaceAnalysis":
                let analyzer = try SurfaceAnalyzer()
                let _ = try await analyzer.analyzeSurface(scanData)
            case "densityAnalysis":
                let _ = try await clinicalAnalysis.analyzeDensity(scanData)
            case "graftPlanning":
                let _ = try await clinicalAnalysis.calculateGraftPlan(
                    scanData: scanData,
                    targetDensity: 65.0
                )
            default:
                break
            }
            
            let endMemory = reportMemoryUsage()
            peakMemory = max(peakMemory, endMemory)
            
            memoryMetrics[component] = (startMemory, peakMemory, endMemory)
            
            // Verify memory cleanup
            XCTAssertLessThan(
                endMemory - startMemory,
                50 * 1024 * 1024,
                "Memory leak detected in \(component)"
            )
        }
        
        // Log memory metrics
        for (component, metrics) in memoryMetrics {
            print("""
                Memory metrics for \(component):
                - Initial: \(metrics.start / 1024 / 1024) MB
                - Peak: \(metrics.peak / 1024 / 1024) MB
                - Final: \(metrics.end / 1024 / 1024) MB
                """)
        }
    }
    
    func testErrorHandling() async throws {
        // Test various error conditions
        let errorCases = [
            "corrupted_scan",
            "invalid_format",
            "incomplete_data"
        ]
        
        for errorCase in errorCases {
            do {
                let scanData = try testDataManager.loadTestScan(type: errorCase)
                let _ = try await clinicalAnalysis.analyzeScan(scanData)
                XCTFail("Expected error for \(errorCase)")
            } catch {
                // Verify appropriate error handling
                XCTAssertNotNil(error)
                switch errorCase {
                case "corrupted_scan":
                    XCTAssertTrue(error is ScanError)
                case "invalid_format":
                    XCTAssertTrue(error is FormatError)
                case "incomplete_data":
                    XCTAssertTrue(error is DataError)
                default:
                    break
                }
            }
        }
    }
    
    private func reportMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
}

// Test data management class
class TestDataManager {
    private let testBundle: Bundle
    
    init() {
        self.testBundle = Bundle.module
    }
    
    func loadTestScan(type: String) throws -> Data {
        guard let url = testBundle.url(forResource: "test_scan_\(type)", withExtension: "obj") else {
            throw TestError.resourceNotFound
        }
        return try Data(contentsOf: url)
    }
}

enum TestError: Error {
    case resourceNotFound
}

enum ScanError: Error {
    case corrupted
}

enum FormatError: Error {
    case invalid
}

enum DataError: Error {
    case incomplete
}