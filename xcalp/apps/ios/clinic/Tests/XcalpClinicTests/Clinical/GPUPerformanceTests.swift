import XCTest
import Metal
@testable import XCalp

class GPUPerformanceTests: XCTestCase {
    var device: MTLDevice!
    var memoryManager: GPUMemoryManager!
    var testScans: TestScans!
    
    override func setUp() {
        super.setUp()
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            XCTFail("GPU not available")
            return
        }
        device = metalDevice
        memoryManager = GPUMemoryManager(device: device)
        testScans = TestScans()
    }
    
    override func tearDown() {
        device = nil
        memoryManager = nil
        testScans = nil
        super.tearDown()
    }
    
    func testCurvatureAnalysisPerformance() async throws {
        let resolutions = [128, 256, 512, 1024]
        var metrics: [Int: Double] = [:]
        
        for resolution in resolutions {
            let analyzer = CurvatureAnalyzer()
            let mesh = createTestMesh(resolution: resolution)
            
            let startTime = CACurrentMediaTime()
            let _ = try await analyzer.analyzeCurvature(mesh)
            let endTime = CACurrentMediaTime()
            
            metrics[resolution] = endTime - startTime
            
            // Performance requirements based on resolution
            let maxAllowedTime = Double(resolution) / 100.0 // Scales with resolution
            XCTAssertLessThan(
                endTime - startTime,
                maxAllowedTime,
                "Curvature analysis too slow for \(resolution)x\(resolution)"
            )
        }
        
        // Log performance metrics
        for (resolution, time) in metrics {
            print("Curvature analysis for \(resolution)x\(resolution): \(String(format: "%.3f", time))s")
        }
    }
    
    func testMemoryChunkingPerformance() async throws {
        let meshSizes = [1_000_000, 2_000_000, 5_000_000] // Number of vertices
        var memoryMetrics: [Int: (time: Double, peakMemory: Int64)] = [:]
        
        for size in meshSizes {
            let mesh = createLargeMesh(vertexCount: size)
            let startTime = CACurrentMediaTime()
            let startMemory = reportMemoryUsage()
            var peakMemory = startMemory
            
            let expectation = XCTestExpectation(description: "Memory chunking")
            
            memoryManager.allocateBuffer(forMesh: mesh) { result in
                switch result {
                case .success(let buffers):
                    // Process each buffer
                    for (index, buffer) in buffers.enumerated() {
                        XCTAssertGreaterThan(buffer.length, 0)
                        self.memoryManager.releaseBuffer(withId: index)
                    }
                case .failure(let error):
                    XCTFail("Failed to allocate buffers: \(error)")
                }
                expectation.fulfill()
            }
            
            await fulfillment(of: [expectation], timeout: 30.0)
            
            let endTime = CACurrentMediaTime()
            let endMemory = reportMemoryUsage()
            peakMemory = max(peakMemory, endMemory)
            
            memoryMetrics[size] = (endTime - startTime, peakMemory - startMemory)
            
            // Verify memory efficiency
            let maxMemoryPerVertex = 32 // bytes
            XCTAssertLessThan(
                peakMemory - startMemory,
                Int64(size * maxMemoryPerVertex),
                "Memory usage too high for \(size) vertices"
            )
        }
        
        // Log memory metrics
        for (size, metrics) in memoryMetrics {
            print("""
                Mesh size \(size) vertices:
                - Processing time: \(String(format: "%.3f", metrics.time))s
                - Peak memory: \(metrics.peakMemory / 1024 / 1024)MB
                """)
        }
    }
    
    func testConcurrentGPUProcessing() async throws {
        let analyzer = CurvatureAnalyzer()
        let meshCount = 4
        let resolution = 512
        
        let startTime = CACurrentMediaTime()
        
        // Process multiple meshes concurrently
        try await withThrowingTaskGroup(of: [[Float]].self) { group in
            for _ in 0..<meshCount {
                group.addTask {
                    let mesh = self.createTestMesh(resolution: resolution)
                    return try await analyzer.analyzeCurvature(mesh)
                }
            }
            
            var completedTasks = 0
            for try await _ in group {
                completedTasks += 1
            }
            
            XCTAssertEqual(completedTasks, meshCount)
        }
        
        let endTime = CACurrentMediaTime()
        let totalTime = endTime - startTime
        
        // Verify concurrent processing is efficient
        let maxTimePerMesh = 1.0 // seconds
        XCTAssertLessThan(
            totalTime,
            Double(meshCount) * maxTimePerMesh,
            "Concurrent processing not efficient"
        )
        
        print("Concurrent processing of \(meshCount) meshes: \(String(format: "%.3f", totalTime))s")
    }
    
    private func createTestMesh(resolution: Int) -> MeshData {
        // Generate test mesh with given resolution
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let xPos = Float(x) / Float(resolution - 1) * 2 - 1
                let yPos = Float(y) / Float(resolution - 1) * 2 - 1
                let zPos = sin(xPos * .pi) * cos(yPos * .pi) * 0.5
                
                vertices.append(SIMD3<Float>(xPos, yPos, zPos))
                normals.append(normalize(SIMD3<Float>(
                    -cos(xPos * .pi) * cos(yPos * .pi),
                    -sin(xPos * .pi) * sin(yPos * .pi),
                    1
                )))
                
                if x < resolution - 1 && y < resolution - 1 {
                    let current = UInt32(y * resolution + x)
                    indices.append(contentsOf: [
                        current, current + 1, current + UInt32(resolution),
                        current + 1, current + UInt32(resolution) + 1, current + UInt32(resolution)
                    ])
                }
            }
        }
        
        return MeshData(vertices: vertices, normals: normals, indices: indices)
    }
    
    private func createLargeMesh(vertexCount: Int) -> MeshData {
        let resolution = Int(sqrt(Double(vertexCount)))
        return createTestMesh(resolution: resolution)
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