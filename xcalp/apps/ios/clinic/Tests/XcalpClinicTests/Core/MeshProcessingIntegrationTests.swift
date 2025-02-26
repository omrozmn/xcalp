import XCTest
import Metal
@testable import xcalp

final class MeshProcessingIntegrationTests: XCTestCase {
    private let device: MTLDevice
    private let dataGenerator: TestDataGenerator
    private let profiler: MeshProcessingProfiler
    private let progress: MeshProcessingProgress
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        self.dataGenerator = TestDataGenerator()
        self.profiler = try MeshProcessingProfiler(device: device)
        self.progress = MeshProcessingProgress()
        try super.init()
    }
    
    func testEndToEndProcessing() async throws {
        // Test complete processing pipeline
        let testCases = [
            (TestMeshGenerator.MeshType.sphere, "optimal"),
            (TestMeshGenerator.MeshType.cube, "poor_lighting"),
            (TestMeshGenerator.MeshType.cylinder, "motion"),
            (TestMeshGenerator.MeshType.noise, "high_noise")
        ]
        
        for (meshType, condition) in testCases {
            try await profiler.beginProfiling("\(meshType)_\(condition)")
            
            let (testMesh, params) = dataGenerator.generateTestData(
                for: .optimal,
                meshType: meshType
            )
            
            // Process mesh through full pipeline
            let processedMesh = try await processMeshWithFullPipeline(testMesh)
            
            // Validate results
            try validateProcessedMesh(processedMesh, original: testMesh, condition: condition)
            
            let metrics = try profiler.endProfiling("\(meshType)_\(condition)")
            validatePerformanceMetrics(metrics, for: condition)
        }
    }
    
    func testPipelineRecovery() async throws {
        // Test recovery from various error conditions
        let recoveryScenarios = [
            (ScanningCondition.poorLighting, 0.3),
            (ScanningCondition.motion, 0.5),
            (ScanningCondition.partialOcclusion, 0.4)
        ]
        
        for (condition, confidence) in recoveryScenarios {
            let (testMesh, _) = dataGenerator.generateTestData(
                for: condition,
                meshType: .sphere
            )
            
            do {
                let processedMesh = try await processMeshWithRecovery(testMesh)
                XCTAssertGreaterThan(
                    calculateAverageConfidence(processedMesh),
                    confidence,
                    "Recovery failed to achieve minimum confidence for \(condition)"
                )
            } catch {
                XCTFail("Recovery failed for \(condition): \(error)")
            }
        }
    }
    
    func testConcurrentProcessing() async throws {
        // Test concurrent mesh processing
        let operations = 5
        var results: [MeshData] = []
        
        try await withThrowingTaskGroup(of: MeshData.self) { group in
            // Start multiple processing operations
            for i in 0..<operations {
                group.addTask {
                    let (testMesh, _) = self.dataGenerator.generateTestData(
                        for: .optimal,
                        meshType: .sphere
                    )
                    return try await self.processMeshWithFullPipeline(testMesh)
                }
            }
            
            // Collect results
            for try await result in group {
                results.append(result)
            }
        }
        
        XCTAssertEqual(results.count, operations, "Not all concurrent operations completed")
        
        // Validate all results
        for result in results {
            try XCTAssertMeshQuality(result)
        }
    }
    
    func testProgressTracking() async throws {
        // Test progress reporting through pipeline stages
        let expectations = [
            expectation(description: "Initialization"),
            expectation(description: "Preprocessing"),
            expectation(description: "Reconstruction"),
            expectation(description: "Optimization"),
            expectation(description: "Completion")
        ]
        
        var observedStages = Set<ProcessingStage>()
        
        let progressSubscription = progress.progressPublisher.sink { update in
            observedStages.insert(update.stage)
            switch update.stage {
            case .initialization:
                expectations[0].fulfill()
            case .preprocessing:
                expectations[1].fulfill()
            case .reconstruction:
                expectations[2].fulfill()
            case .optimization:
                expectations[3].fulfill()
            case .completion:
                expectations[4].fulfill()
            }
        }
        
        // Process test mesh
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        progress.beginOperation("progress_test")
        
        let processedMesh = try await processMeshWithProgress(
            testMesh,
            progress: progress
        )
        
        // Wait for all stages
        wait(for: expectations, timeout: 30.0)
        
        XCTAssertEqual(observedStages.count, 5, "Not all processing stages were observed")
        try XCTAssertMeshQuality(processedMesh)
        
        progressSubscription.cancel()
    }
    
    func testQualityPreservation() async throws {
        // Test quality preservation across pipeline stages
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        var qualityMetrics: [ProcessingStage: QualityMetrics] = [:]
        
        // Process mesh stage by stage
        for stage in ProcessingStage.allCases {
            let processed = try await processMeshWithProgress(
                testMesh,
                currentStage: stage,
                progress: progress
            )
            
            qualityMetrics[stage] = try MeshValidation.validateTopology(processed)
        }
        
        // Verify quality metrics don't degrade
        for stage in ProcessingStage.allCases.dropFirst() {
            guard let previous = qualityMetrics[ProcessingStage.allCases[stage.rawValue - 1]],
                  let current = qualityMetrics[stage] else {
                continue
            }
            
            XCTAssertGreaterThanOrEqual(
                current.surfaceCompleteness,
                previous.surfaceCompleteness * 0.9,
                "Quality degraded significantly at \(stage)"
            )
        }
    }
    
    private func validateProcessedMesh(_ processed: MeshData, original: MeshData, condition: String) throws {
        // Validate mesh properties
        try XCTAssertMeshQuality(processed)
        
        // Validate topology
        let topology = try MeshValidation.validateTopology(processed)
        XCTAssertTrue(topology.isManifold, "Processed mesh is not manifold")
        
        // Validate confidence
        let averageConfidence = calculateAverageConfidence(processed)
        XCTAssertGreaterThan(averageConfidence, 0.5, "Low confidence in processed mesh")
    }
    
    private func validatePerformanceMetrics(_ metrics: ProfileMetrics, for condition: String) {
        XCTAssertLessThan(
            metrics.cpuTime,
            TestConfiguration.maxProcessingTime,
            "Processing time exceeded limit for \(condition)"
        )
        
        XCTAssertLessThan(
            metrics.memoryPeak,
            UInt64(TestConfiguration.maxMemoryUsage),
            "Memory usage exceeded limit for \(condition)"
        )
    }
    
    private func calculateAverageConfidence(_ mesh: MeshData) -> Float {
        return mesh.confidence.reduce(0, +) / Float(mesh.confidence.count)
    }
}

// Test helper extensions
private extension ProcessingStage {
    var rawValue: Int {
        switch self {
        case .initialization: return 0
        case .preprocessing: return 1
        case .reconstruction: return 2
        case .optimization: return 3
        case .qualityAnalysis: return 4
        case .completion: return 5
        }
    }
    
    static var allCases: [ProcessingStage] {
        return [
            .initialization,
            .preprocessing,
            .reconstruction,
            .optimization,
            .qualityAnalysis,
            .completion
        ]
    }
}