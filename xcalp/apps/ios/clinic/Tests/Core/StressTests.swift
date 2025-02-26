import XCTest
import Metal
@testable import xcalp

final class StressTests: MeshProcessingTestFixture {
    private let stressTest: MeshProcessingStressTest!
    private let errorInjector: ErrorInjector!
    private let memorySimulator: MemoryPressureSimulator!
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.stressTest = MeshProcessingStressTest(device: device)
        self.errorInjector = ErrorInjector()
        self.memorySimulator = MemoryPressureSimulator()
        try super.init()
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyMesh() async throws {
        let emptyMesh = MeshData(
            vertices: [],
            indices: [],
            normals: [],
            confidence: [],
            metadata: MeshMetadata(source: .test)
        )
        
        do {
            _ = try await processMeshWithFullPipeline(emptyMesh)
            XCTFail("Should throw error for empty mesh")
        } catch {
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    func testGiantMesh() async throws {
        // Test with a mesh that exceeds normal size limits
        let giantMesh = TestMeshGenerator.generateTestMesh(
            .sphere,
            resolution: 1024 // Creates very large mesh
        )
        
        do {
            let result = try await processMeshWithFullPipeline(giantMesh)
            
            // Verify processing succeeded and maintained quality
            try validateMeshTopology(result)
            XCTAssertLessThan(
                result.vertices.count,
                giantMesh.vertices.count,
                "Giant mesh not optimized"
            )
        } catch {
            XCTFail("Failed to process giant mesh: \(error)")
        }
    }
    
    func testDegenerateMesh() async throws {
        // Create mesh with degenerate triangles
        let mesh = createDegenerateMesh()
        
        do {
            let result = try await processMeshWithFullPipeline(mesh)
            
            // Verify degenerate triangles were handled
            try validateNoDegenerateTriangles(result)
        } catch {
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    // MARK: - Error Injection Tests
    
    func testRandomErrorInjection() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        let config = ErrorInjector.InjectionConfig(
            errorType: .corruptedVertices,
            probability: 0.5,
            severity: 0.3,
            metadata: [:]
        )
        
        let corruptedMesh = errorInjector.injectError(into: testMesh, config: config)
        
        do {
            let result = try await processMeshWithFullPipeline(corruptedMesh)
            
            // Verify recovery and quality
            try validateMeshTopology(result)
            try validateProcessingResult(input: testMesh, output: result)
        } catch {
            XCTFail("Failed to handle corrupted mesh: \(error)")
        }
    }
    
    func testCascadingErrors() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        
        // Inject multiple cascading errors
        var corruptedMesh = errorInjector.injectError(
            into: testMesh,
            config: .init(errorType: .corruptedVertices, probability: 1.0, severity: 0.2, metadata: [:])
        )
        
        corruptedMesh = errorInjector.injectError(
            into: corruptedMesh,
            config: .init(errorType: .invalidIndices, probability: 1.0, severity: 0.2, metadata: [:])
        )
        
        do {
            let result = try await processMeshWithFullPipeline(corruptedMesh)
            try validateMeshTopology(result)
        } catch {
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryPressure() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        
        try await memorySimulator.simulateMemoryPressure(level: 3) {
            let result = try await processMeshWithFullPipeline(testMesh)
            try validateMeshTopology(result)
        }
    }
    
    func testMemoryExhaustion() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 256)
        
        // Process under extreme memory pressure
        try await memorySimulator.simulateMemoryPressure(level: 4) {
            do {
                _ = try await processMeshWithFullPipeline(testMesh)
            } catch {
                XCTAssertTrue(error is OutOfMemoryError)
                // Verify system remained stable
                XCTAssertLessThan(getMemoryUsage(), UInt64(TestConfiguration.maxMemoryUsage))
            }
        }
    }
    
    // MARK: - Concurrent Stress Tests
    
    func testConcurrentErrorScenarios() async throws {
        let meshCount = 10
        let meshes = (0..<meshCount).map { _ in
            TestMeshGenerator.generateTestMesh(.sphere)
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for mesh in meshes {
                group.addTask {
                    // Randomly inject errors and process under pressure
                    let corruptedMesh = self.errorInjector.injectError(
                        into: mesh,
                        config: .standard
                    )
                    
                    try await self.memorySimulator.simulateMemoryPressure(level: 2) {
                        _ = try await self.processMeshWithFullPipeline(corruptedMesh)
                    }
                }
            }
            
            do {
                try await group.waitForAll()
            } catch {
                // Verify partial completion
                XCTAssertGreaterThan(group.completedCount, 0)
            }
        }
    }
    
    func testResourceExhaustion() async throws {
        let config = MeshProcessingStressTest.StressTestConfig(
            duration: 300, // 5 minutes
            maxMeshSize: 1_000_000,
            concurrencyLevel: 8,
            memoryPressure: 0.9,
            errorRate: 0.2
        )
        
        let results = try await stressTest.runStressTest(config: config)
        
        // Verify system stability
        XCTAssertGreaterThan(results.successRate, 0.8)
        XCTAssertLessThan(
            results.peakMemoryUsage,
            UInt64(TestConfiguration.maxMemoryUsage)
        )
    }
    
    // MARK: - Recovery Tests
    
    func testRecoveryFromCorruption() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        var recoveryAttempts = 0
        
        let result = try await withRetry(maxAttempts: 3) {
            recoveryAttempts += 1
            let corruptedMesh = self.errorInjector.injectError(
                into: testMesh,
                config: .standard
            )
            return try await self.processMeshWithFullPipeline(corruptedMesh)
        }
        
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(recoveryAttempts, 0)
        try validateMeshTopology(result!)
    }
    
    // MARK: - Helper Methods
    
    private func createDegenerateMesh() -> MeshData {
        var mesh = TestMeshGenerator.generateTestMesh(.sphere)
        
        // Make some triangles degenerate
        for i in stride(from: 0, to: mesh.vertices.count, by: 3) {
            mesh.vertices[i] = mesh.vertices[min(i + 1, mesh.vertices.count - 1)]
        }
        
        return mesh
    }
    
    private func validateNoDegenerateTriangles(_ mesh: MeshData) throws {
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            let area = length(cross(v2 - v1, v3 - v1)) * 0.5
            XCTAssertGreaterThan(area, 1e-6, "Degenerate triangle found")
        }
    }
    
    private func withRetry<T>(
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T? {
        var lastError: Error?
        
        for _ in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? ProcessingError.maxRetriesExceeded
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
}