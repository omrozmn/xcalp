import XCTest
@testable import XcalpClinic

final class MeshProcessingTests: XCTestCase {
    var processor: MeshProcessor!
    
    override func setUp() async throws {
        try await super.setUp()
        processor = try MeshProcessor()
    }
    
    override func tearDown() async throws {
        processor = nil
        try await super.tearDown()
    }
    
    func testMeshOptimization() async throws {
        // Create test mesh data
        let testMesh = createTestMeshData(vertexCount: 10000)
        
        // Process mesh
        let processedMesh = try await processor.processMesh(testMesh)
        
        // Verify optimization
        XCTAssertLessThan(
            processedMesh.metrics.optimizedVertexCount,
            processedMesh.metrics.originalVertexCount,
            "Mesh should be optimized with fewer vertices"
        )
        
        // Verify quality
        XCTAssertGreaterThanOrEqual(processedMesh.quality.normalConsistency, 0.8)
        XCTAssertGreaterThanOrEqual(processedMesh.quality.surfaceSmoothness, 0.7)
    }
    
    func testMeshValidation() async throws {
        // Test with poor quality mesh
        let poorMesh = createTestMeshData(vertexCount: 100) // Too few vertices
        
        await XCTAssertThrowsError(try await processor.processMesh(poorMesh)) { error in
            guard case ScanningError.meshValidationFailed(let issues) = error else {
                XCTFail("Expected meshValidationFailed error")
                return
            }
            
            XCTAssertTrue(issues.contains(where: { 
                if case .tooFewVertices = $0 { return true }
                return false
            }))
        }
    }
    
    func testPerformance() async throws {
        let largeMesh = createTestMeshData(vertexCount: 100000)
        
        measure {
            let expectation = expectation(description: "Mesh Processing")
            
            Task {
                do {
                    let processed = try await processor.processMesh(largeMesh)
                    XCTAssertLessThan(processed.metrics.processingTime, 5.0) // Should process in under 5 seconds
                    expectation.fulfill()
                } catch {
                    XCTFail("Processing failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // Helper methods
    private func createTestMeshData(vertexCount: Int) -> Data {
        var data = Data()
        
        // Create vertices
        for _ in 0..<vertexCount {
            let vertex = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            data.append(contentsOf: withUnsafeBytes(of: vertex) { Array($0) })
        }
        
        // Create indices for triangles
        for i in stride(from: 0, to: vertexCount - 2, by: 3) {
            let indices = [UInt32(i), UInt32(i + 1), UInt32(i + 2)]
            data.append(contentsOf: withUnsafeBytes(of: indices) { Array($0) })
        }
        
        return data
    }
}