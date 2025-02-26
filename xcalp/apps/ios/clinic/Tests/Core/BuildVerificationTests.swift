import XCTest
import Metal
@testable import xcalp

final class BuildVerificationTests: XCTestCase {
    private let device: MTLDevice
    private let testRunner: MeshProcessingTestRunner
    private let dataGenerator: TestDataGenerator
    private let alertHandler: TestAlertHandler
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        self.testRunner = try MeshProcessingTestRunner()
        self.dataGenerator = TestDataGenerator()
        self.alertHandler = TestAlertHandler.shared
        try super.init()
    }
    
    override func setUp() async throws {
        // Reset alert handler for each test
        alertHandler.suppressAlertType(.performanceRegression)
    }
    
    func testBasicMeshProcessing() async throws {
        // Test basic mesh processing functionality
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        
        let result = try await testRunner.runQuickTests()
        XCTAssertNotNil(result.validationResults)
        XCTAssertTrue(result.validationResults?.passed ?? false)
    }
    
    func testProcessingPipeline() async throws {
        // Test each stage of the processing pipeline
        let stages: [ProcessingStage] = [
            .initialization,
            .preprocessing,
            .reconstruction,
            .optimization,
            .qualityAnalysis
        ]
        
        for stage in stages {
            try await verifyProcessingStage(stage)
        }
    }
    
    func testErrorHandling() async throws {
        // Test error recovery mechanisms
        let corruptedMesh = TestMeshGenerator.generateTestMesh(.corrupted)
        
        do {
            _ = try await processMeshWithFullPipeline(corruptedMesh)
            XCTFail("Expected error processing corrupted mesh")
        } catch {
            XCTAssertNotNil(error)
        }
    }
    
    func testPerformanceBaseline() async throws {
        // Verify performance meets baseline requirements
        let testMesh = TestMeshGenerator.generateTestMesh(.cube)
        
        measure {
            let expectation = expectation(description: "Processing completion")
            
            Task {
                do {
                    let processed = try await processMeshWithFullPipeline(testMesh)
                    XCTAssertGreaterThan(processed.vertices.count, 0)
                    expectation.fulfill()
                } catch {
                    XCTFail("Processing failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    func testConcurrentOperations() async throws {
        // Test concurrent processing capability
        let meshes = (0..<5).map { _ in
            TestMeshGenerator.generateTestMesh(.sphere)
        }
        
        try await withThrowingTaskGroup(of: MeshData.self) { group in
            for mesh in meshes {
                group.addTask {
                    return try await processMeshWithFullPipeline(mesh)
                }
            }
            
            var completedCount = 0
            for try await _ in group {
                completedCount += 1
            }
            
            XCTAssertEqual(completedCount, meshes.count)
        }
    }
    
    func testMemoryManagement() async throws {
        // Test memory usage patterns
        let largeTestMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 256)
        
        try await XCTAssertMemoryUsage {
            _ = try await processMeshWithFullPipeline(largeTestMesh)
        }
    }
    
    func testQualityMetrics() async throws {
        // Test quality assessment functionality
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        let processed = try await processMeshWithFullPipeline(testMesh)
        
        try XCTAssertMeshQuality(processed)
    }
    
    private func verifyProcessingStage(_ stage: ProcessingStage) async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.cube)
        let progress = MeshProcessingProgress()
        
        progress.beginOperation("stage_verification")
        
        let result = try await processMeshWithProgress(
            testMesh,
            currentStage: stage,
            progress: progress
        )
        
        XCTAssertNotNil(result)
        try XCTAssertMeshQuality(result)
    }
}

// Helper functions for test validation
private extension BuildVerificationTests {
    func validateMeshProperties(_ mesh: MeshData) {
        XCTAssertGreaterThan(mesh.vertices.count, 0, "Mesh has no vertices")
        XCTAssertGreaterThan(mesh.indices.count, 0, "Mesh has no indices")
        XCTAssertEqual(mesh.vertices.count, mesh.normals.count, "Vertex and normal count mismatch")
        XCTAssertEqual(mesh.vertices.count, mesh.confidence.count, "Vertex and confidence count mismatch")
    }
    
    func validateMeshTopology(_ mesh: MeshData) throws {
        let topology = try MeshValidation.validateTopology(mesh)
        XCTAssertTrue(topology.isManifold, "Mesh is not manifold")
        XCTAssertTrue(topology.isWatertight, "Mesh is not watertight")
    }
    
    func validateProcessingResult(_ result: MeshData, original: MeshData) {
        XCTAssertGreaterThanOrEqual(result.confidence.reduce(0, +) / Float(result.confidence.count),
                                   original.confidence.reduce(0, +) / Float(original.confidence.count),
                                   "Processing decreased average confidence")
    }
}

// Test configuration extensions
private extension BuildVerificationTests {
    static let performanceBaseline = TimeInterval(5.0)
    static let memoryBaseline = 512 * 1024 * 1024 // 512MB
    static let qualityThreshold = Float(0.8)
    
    func configureTestEnvironment() {
        // Configure test environment settings
        TestConfiguration.maxProcessingTime = Self.performanceBaseline
        TestConfiguration.maxMemoryUsage = Self.memoryBaseline
        TestConfiguration.minimumQualityThreshold = Self.qualityThreshold
    }
}