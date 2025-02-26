import XCTest
import Metal
@testable import xcalp

final class PerformanceBenchmarkTests: MeshProcessingTestFixture {
    private var benchmark: MeshProcessingBenchmark!
    private var profiler: MeshProcessingProfiler!
    
    override func setUp() {
        super.setUp()
        benchmark = try! MeshProcessingBenchmark(device: device)
        profiler = try! MeshProcessingProfiler(device: device)
    }
    
    override func tearDown() {
        benchmark = nil
        profiler = nil
        super.tearDown()
    }
    
    func testProcessingThroughput() async throws {
        // Test processing speed with different mesh sizes
        let meshSizes = [1000, 10000, 100000]
        let iterations = 5
        
        for size in meshSizes {
            var totalTime: TimeInterval = 0
            var peakMemory: UInt64 = 0
            
            for _ in 0...iterations {
                let testMesh = TestMeshGenerator.generateTestMesh(
                    .sphere,
                    resolution: Int(sqrt(Float(size)))
                )
                
                try await profiler.beginProfiling("throughput_test_\(size)")
                _ = try await processMeshWithFullPipeline(testMesh)
                let metrics = try await profiler.endProfiling("throughput_test_\(size)")
                
                totalTime += metrics.cpuTime
                peakMemory = max(peakMemory, metrics.memoryPeak)
            }
            
            let averageTime = totalTime / Double(iterations)
            let throughput = Double(size) / averageTime
            
            // Verify performance meets requirements
            XCTAssertGreaterThan(
                throughput,
                Double(size) / TestConfiguration.maxProcessingTime,
                "Processing throughput below threshold for size \(size)"
            )
            
            XCTAssertLessThan(
                peakMemory,
                UInt64(TestConfiguration.maxMemoryUsage),
                "Memory usage exceeded limit for size \(size)"
            )
        }
    }
    
    func testConcurrentPerformance() async throws {
        let concurrencyLevels = [1, 2, 4, 8]
        let meshSize = 10000
        let testMesh = TestMeshGenerator.generateTestMesh(
            .sphere,
            resolution: Int(sqrt(Float(meshSize)))
        )
        
        for level in concurrencyLevels {
            try await profiler.beginProfiling("concurrent_test_\(level)")
            
            try await withThrowingTaskGroup(of: MeshData.self) { group in
                for _ in 0..<level {
                    group.addTask {
                        return try await self.processMeshWithFullPipeline(testMesh)
                    }
                }
                
                var completed = 0
                for try await _ in group {
                    completed += 1
                }
                
                XCTAssertEqual(completed, level, "Not all concurrent operations completed")
            }
            
            let metrics = try await profiler.endProfiling("concurrent_test_\(level)")
            
            // Verify concurrent performance
            let timePerOperation = metrics.cpuTime / Double(level)
            XCTAssertLessThan(
                timePerOperation,
                TestConfiguration.maxProcessingTime,
                "Concurrent processing time exceeded limit"
            )
        }
    }
    
    func testMemoryScaling() async throws {
        let meshSizes = [1000, 10000, 100000, 1000000]
        
        for size in meshSizes {
            let testMesh = TestMeshGenerator.generateTestMesh(
                .sphere,
                resolution: Int(sqrt(Float(size)))
            )
            
            try await profiler.beginProfiling("memory_test_\(size)")
            _ = try await processMeshWithFullPipeline(testMesh)
            let metrics = try await profiler.endProfiling("memory_test_\(size)")
            
            // Verify linear memory scaling
            let bytesPerVertex = Double(metrics.memoryPeak) / Double(size)
            XCTAssertLessThan(
                bytesPerVertex,
                1000,
                "Memory usage per vertex exceeded threshold"
            )
        }
    }
    
    func testGPUUtilization() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 128)
        
        try await profiler.beginProfiling("gpu_utilization")
        _ = try await processMeshWithFullPipeline(testMesh)
        let metrics = try await profiler.endProfiling("gpu_utilization")
        
        // Verify GPU utilization
        let gpuUtilization = metrics.gpuTime / metrics.cpuTime
        XCTAssertGreaterThan(
            gpuUtilization,
            0.5,
            "GPU utilization below threshold"
        )
    }
    
    func testProcessingLatency() async throws {
        let iterations = 100
        var latencies: [TimeInterval] = []
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 32)
        
        for _ in 0..<iterations {
            let startTime = CACurrentMediaTime()
            _ = try await processMeshWithFullPipeline(testMesh)
            latencies.append(CACurrentMediaTime() - startTime)
        }
        
        // Calculate latency statistics
        let averageLatency = latencies.reduce(0, +) / Double(iterations)
        let variance = latencies.map { pow($0 - averageLatency, 2) }.reduce(0, +) / Double(iterations)
        let stdDev = sqrt(variance)
        
        // Verify latency characteristics
        XCTAssertLessThan(
            averageLatency,
            TestConfiguration.maxProcessingTime,
            "Average latency exceeded threshold"
        )
        
        XCTAssertLessThan(
            stdDev / averageLatency, // Coefficient of variation
            0.2,
            "Processing latency variation too high"
        )
    }
    
    func testResourceEfficiency() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 64)
        var baselineMemory: UInt64 = 0
        var peakMemory: UInt64 = 0
        
        // Measure baseline memory
        autoreleasepool {
            baselineMemory = getMemoryUsage()
        }
        
        // Process mesh and track memory
        try await profiler.beginProfiling("resource_efficiency")
        _ = try await processMeshWithFullPipeline(testMesh)
        let metrics = try await profiler.endProfiling("resource_efficiency")
        
        autoreleasepool {
            peakMemory = getMemoryUsage()
        }
        
        // Verify memory cleanup
        XCTAssertLessThan(
            Double(peakMemory - baselineMemory) / Double(baselineMemory),
            0.5,
            "Excessive memory retention after processing"
        )
        
        // Verify resource release
        XCTAssertLessThan(
            metrics.gpuMemoryPeak,
            UInt64(TestConfiguration.maxMemoryUsage / 2),
            "Excessive GPU memory usage"
        )
    }
    
    func testProcessingStability() async throws {
        let iterations = 50
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: 64)
        var results: [MeshData] = []
        
        // Process same mesh multiple times
        for _ in 0..<iterations {
            let result = try await processMeshWithFullPipeline(testMesh)
            results.append(result)
        }
        
        // Verify consistent results
        for i in 1..<results.count {
            let previousHash = generateMeshHash(results[i-1])
            let currentHash = generateMeshHash(results[i])
            
            XCTAssertEqual(
                previousHash,
                currentHash,
                "Processing results not consistent across iterations"
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func generateMeshHash(_ mesh: MeshData) -> Int {
        var hasher = Hasher()
        mesh.vertices.forEach { hasher.combine($0) }
        mesh.normals.forEach { hasher.combine($0) }
        return hasher.finalize()
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