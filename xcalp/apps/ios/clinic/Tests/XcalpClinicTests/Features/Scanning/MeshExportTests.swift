import ModelIO
@testable import XcalpClinic
import XCTest

final class MeshExportTests: XCTestCase {
    var processor: MeshProcessor!
    
    override func setUp() async throws {
        try await super.setUp()
        processor = try MeshProcessor()
    }
    
    override func tearDown() async throws {
        processor = nil
        try await super.tearDown()
    }
    
    func testOBJExport() async throws {
        let testMesh = createTestMeshData(vertexCount: 1000)
        let processedMesh = try await processor.processMesh(testMesh)
        
        let exportedData = try MeshExporter.export(processedMesh, format: .obj)
        XCTAssertFalse(exportedData.isEmpty)
        
        // Verify OBJ format
        let objString = String(data: exportedData, encoding: .utf8)
        XCTAssertNotNil(objString)
        XCTAssertTrue(objString!.contains("v ")) // Has vertices
        XCTAssertTrue(objString!.contains("vn ")) // Has normals
        XCTAssertTrue(objString!.contains("vt ")) // Has UVs
        XCTAssertTrue(objString!.contains("f ")) // Has faces
    }
    
    func testUSDZExport() async throws {
        let testMesh = createTestMeshData(vertexCount: 1000)
        let processedMesh = try await processor.processMesh(testMesh)
        
        let exportedData = try MeshExporter.export(processedMesh, format: .usdz)
        XCTAssertFalse(exportedData.isEmpty)
        
        // Verify USDZ format
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.usdz")
        try exportedData.write(to: url)
        
        let asset = MDLAsset(url: url)
        XCTAssertFalse(asset.meshes.isEmpty)
        XCTAssertTrue(asset.meshes.first?.vertexCount == processedMesh.metrics.optimizedVertexCount)
    }
    
    func testExportWithMetadata() async throws {
        let testMesh = createTestMeshData(vertexCount: 1000)
        let processedMesh = try await processor.processMesh(testMesh)
        
        let metadata = MeshExporter.createMetadata(for: processedMesh, format: .obj)
        
        XCTAssertEqual(metadata["contentType"] as? String, "model/obj")
        XCTAssertEqual(metadata["vertexCount"] as? Int, processedMesh.metrics.optimizedVertexCount)
        
        let quality = metadata["quality"] as? [String: Float]
        XCTAssertNotNil(quality)
        XCTAssertNotNil(quality?["vertexDensity"])
        XCTAssertNotNil(quality?["surfaceSmoothness"])
        XCTAssertNotNil(quality?["normalConsistency"])
    }
    
    // Helper methods
    private func createTestMeshData(vertexCount: Int) -> Data {
        var data = Data()
        
        // Create vertices in a sphere pattern for better test mesh
        for i in 0..<vertexCount {
            let phi = acos(-1.0 + 2.0 * Double(i) / Double(vertexCount))
            let theta = sqrt(Double(vertexCount) * Double.pi) * phi
            
            let vertex = SIMD3<Float>(
                Float(cos(theta) * sin(phi)),
                Float(sin(theta) * sin(phi)),
                Float(cos(phi))
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
