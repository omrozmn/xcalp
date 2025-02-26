import XCTest
import simd

extension XCTestCase {
    // Quality assertions
    func XCTAssertMeshQuality(
        _ mesh: MeshData,
        minimumDensity: Float = TestConfiguration.minimumPointDensity,
        minimumCompleteness: Float = TestConfiguration.minimumSurfaceCompleteness,
        maximumNoise: Float = TestConfiguration.maximumNoiseLevel,
        minimumFeatures: Float = TestConfiguration.minimumFeaturePreservation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let metrics = try MeshValidation.validateTopology(mesh)
        let quality = mesh.calculateQualityMetrics()
        
        XCTAssertGreaterThanOrEqual(
            quality.pointDensity,
            minimumDensity,
            "Point density below threshold",
            file: file,
            line: line
        )
        
        XCTAssertGreaterThanOrEqual(
            quality.surfaceCompleteness,
            minimumCompleteness,
            "Surface completeness below threshold",
            file: file,
            line: line
        )
        
        XCTAssertLessThanOrEqual(
            quality.noiseLevel,
            maximumNoise,
            "Noise level above threshold",
            file: file,
            line: line
        )
        
        XCTAssertGreaterThanOrEqual(
            quality.featurePreservation,
            minimumFeatures,
            "Feature preservation below threshold",
            file: file,
            line: line
        )
        
        XCTAssertTrue(
            metrics.isManifold,
            "Mesh is not manifold",
            file: file,
            line: line
        )
    }
    
    // Performance assertions
    func XCTAssertProcessingPerformance(
        _ operation: () async throws -> MeshData,
        timeout: TimeInterval = TestConfiguration.operationTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let startTime = CACurrentMediaTime()
        let result = try await operation()
        let duration = CACurrentMediaTime() - startTime
        
        XCTAssertLessThanOrEqual(
            duration,
            timeout,
            "Processing time exceeded timeout",
            file: file,
            line: line
        )
        
        try XCTAssertMeshQuality(result, file: file, line: line)
    }
    
    // Memory assertions
    func XCTAssertMemoryUsage(
        _ operation: () async throws -> Void,
        maxMemory: Int = TestConfiguration.maxMemoryUsage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let startMemory = getMemoryUsage()
        try await operation()
        let peakMemory = getMemoryUsage() - startMemory
        
        XCTAssertLessThanOrEqual(
            peakMemory,
            maxMemory,
            "Memory usage exceeded limit",
            file: file,
            line: line
        )
    }
    
    // Mesh comparison assertions
    func XCTAssertMeshesEqual(
        _ mesh1: MeshData,
        _ mesh2: MeshData,
        tolerance: Float = 1e-6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            mesh1.vertices.count,
            mesh2.vertices.count,
            "Vertex count mismatch",
            file: file,
            line: line
        )
        
        XCTAssertEqual(
            mesh1.indices.count,
            mesh2.indices.count,
            "Index count mismatch",
            file: file,
            line: line
        )
        
        for (i, (v1, v2)) in zip(mesh1.vertices, mesh2.vertices).enumerated() {
            XCTAssertEqual(
                distance(v1, v2),
                0,
                accuracy: tolerance,
                "Vertex \(i) position mismatch",
                file: file,
                line: line
            )
        }
        
        for (i, (n1, n2)) in zip(mesh1.normals, mesh2.normals).enumerated() {
            XCTAssertEqual(
                distance(n1, n2),
                0,
                accuracy: tolerance,
                "Normal \(i) direction mismatch",
                file: file,
                line: line
            )
        }
    }
    
    // Async test helpers
    func XCTAssertEventuallyEqual<T: Equatable>(
        _ expression: @escaping () async throws -> T,
        _ expectedValue: T,
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            do {
                let result = try await expression()
                if result == expectedValue {
                    return
                }
            } catch {
                // Continue polling on error
            }
            
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        
        // Final attempt
        let finalResult = try await expression()
        XCTAssertEqual(
            finalResult,
            expectedValue,
            file: file,
            line: line
        )
    }
    
    private func getMemoryUsage() -> Int {
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
        
        return kerr == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}