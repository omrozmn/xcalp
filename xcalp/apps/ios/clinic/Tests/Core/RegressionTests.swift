import XCTest
import Metal
@testable import xcalp

final class RegressionTests: XCTestCase {
    private let device: MTLDevice
    private let dataGenerator: TestDataGenerator
    private let benchmarkSuite: MeshProcessingBenchmark
    private let baselinePath: URL
    
    struct Baseline: Codable {
        let version: String
        let timestamp: Date
        let metrics: [String: BaselineMetrics]
        
        struct BaselineMetrics: Codable {
            let processingTime: TimeInterval
            let memoryUsage: UInt64
            let qualityScore: Float
            let hash: String
        }
    }
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        self.dataGenerator = TestDataGenerator()
        self.benchmarkSuite = MeshProcessingBenchmark(device: device)
        
        // Set up baseline path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baselinePath = documentsPath.appendingPathComponent("regression_baseline.json")
        
        try super.init()
    }
    
    override func setUp() async throws {
        // Create baseline if it doesn't exist
        if !FileManager.default.fileExists(atPath: baselinePath.path) {
            try await generateBaseline()
        }
    }
    
    func testPerformanceRegression() async throws {
        let baseline = try loadBaseline()
        let testCases = createRegressionTestCases()
        
        for testCase in testCases {
            let metrics = try await measurePerformance(for: testCase)
            
            guard let baselineMetrics = baseline.metrics[testCase.identifier] else {
                throw RegressionError.missingBaseline(testCase.identifier)
            }
            
            // Compare with baseline
            let timeRegression = (metrics.processingTime - baselineMetrics.processingTime) / baselineMetrics.processingTime
            let memoryRegression = Float(metrics.memoryUsage - baselineMetrics.memoryUsage) / Float(baselineMetrics.memoryUsage)
            let qualityRegression = (baselineMetrics.qualityScore - metrics.qualityScore) / baselineMetrics.qualityScore
            
            // Assert no significant regressions
            XCTAssertLessThan(timeRegression, 0.1, "Performance regression in \(testCase.identifier)")
            XCTAssertLessThan(memoryRegression, 0.1, "Memory usage regression in \(testCase.identifier)")
            XCTAssertLessThan(qualityRegression, 0.05, "Quality regression in \(testCase.identifier)")
            
            // Verify result consistency
            XCTAssertEqual(
                metrics.hash,
                baselineMetrics.hash,
                "Processing result differs from baseline for \(testCase.identifier)"
            )
        }
    }
    
    func testFeatureRegression() async throws {
        // Test specific features for regression
        let features = [
            RegressionFeature.normalEstimation,
            .featurePreservation,
            .noiseReduction,
            .meshOptimization
        ]
        
        for feature in features {
            let result = try await testFeature(feature)
            XCTAssertTrue(result.passed, "Regression in feature: \(feature)")
            
            if let baseline = try? loadFeatureBaseline(feature) {
                XCTAssertGreaterThanOrEqual(
                    result.score,
                    baseline.score * 0.95,
                    "Feature quality regression: \(feature)"
                )
            }
        }
    }
    
    func testQualityRegression() async throws {
        let baseline = try loadBaseline()
        let testCases = createQualityTestCases()
        
        for testCase in testCases {
            let metrics = try await measureQuality(for: testCase)
            
            guard let baselineMetrics = baseline.metrics[testCase.identifier] else {
                throw RegressionError.missingBaseline(testCase.identifier)
            }
            
            // Compare quality metrics
            XCTAssertGreaterThanOrEqual(
                metrics.qualityScore,
                baselineMetrics.qualityScore * 0.95,
                "Quality regression in \(testCase.identifier)"
            )
        }
    }
    
    private func generateBaseline() async throws {
        var baseline = Baseline(
            version: "1.0",
            timestamp: Date(),
            metrics: [:]
        )
        
        // Generate baseline metrics
        let testCases = createRegressionTestCases()
        for testCase in testCases {
            let metrics = try await measurePerformance(for: testCase)
            baseline.metrics[testCase.identifier] = metrics
        }
        
        // Save baseline
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(baseline)
        try data.write(to: baselinePath)
    }
    
    private func loadBaseline() throws -> Baseline {
        let data = try Data(contentsOf: baselinePath)
        let decoder = JSONDecoder()
        decoder.dateEncodingStrategy = .iso8601
        return try decoder.decode(Baseline.self, from: data)
    }
    
    private func measurePerformance(
        for testCase: RegressionTestCase
    ) async throws -> Baseline.BaselineMetrics {
        let (testMesh, _) = dataGenerator.generateTestData(
            for: testCase.condition,
            meshType: testCase.meshType
        )
        
        let startTime = CACurrentMediaTime()
        let startMemory = getMemoryUsage()
        
        let processedMesh = try await processMeshWithFullPipeline(testMesh)
        
        let endTime = CACurrentMediaTime()
        let endMemory = getMemoryUsage()
        
        return Baseline.BaselineMetrics(
            processingTime: endTime - startTime,
            memoryUsage: endMemory - startMemory,
            qualityScore: try calculateQualityScore(processedMesh),
            hash: generateResultHash(processedMesh)
        )
    }
    
    private func getMemoryUsage() -> UInt64 {
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
        
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    
    private func calculateQualityScore(_ mesh: MeshData) throws -> Float {
        let metrics = try MeshValidation.validateTopology(mesh)
        let quality = mesh.calculateQualityMetrics()
        
        return (quality.surfaceCompleteness +
                quality.featurePreservation +
                (1.0 - quality.noiseLevel)) / 3.0
    }
    
    private func generateResultHash(_ mesh: MeshData) -> String {
        // Generate a hash of the mesh data for consistency checking
        var hasher = Hasher()
        mesh.vertices.forEach { hasher.combine($0) }
        mesh.normals.forEach { hasher.combine($0) }
        return String(hasher.finalize())
    }
}

struct RegressionTestCase {
    let identifier: String
    let meshType: TestMeshGenerator.MeshType
    let condition: ScanningCondition
}

enum RegressionFeature {
    case normalEstimation
    case featurePreservation
    case noiseReduction
    case meshOptimization
}

enum RegressionError: Error {
    case missingBaseline(String)
    case featureRegression(RegressionFeature)
    case invalidBaseline
}

private extension RegressionTests {
    func createRegressionTestCases() -> [RegressionTestCase] {
        return [
            RegressionTestCase(identifier: "sphere_optimal", meshType: .sphere, condition: .optimal),
            RegressionTestCase(identifier: "cube_noisy", meshType: .cube, condition: .highNoise),
            RegressionTestCase(identifier: "cylinder_motion", meshType: .cylinder, condition: .motion)
        ]
    }
    
    func createQualityTestCases() -> [RegressionTestCase] {
        return [
            RegressionTestCase(identifier: "quality_sphere", meshType: .sphere, condition: .optimal),
            RegressionTestCase(identifier: "quality_features", meshType: .cube, condition: .optimal)
        ]
    }
}