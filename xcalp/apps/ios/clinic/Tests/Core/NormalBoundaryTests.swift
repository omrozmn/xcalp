import XCTest
import Metal
@testable import xcalp


final class NormalBoundaryTests: MeshProcessingTestFixture {
    private var normalProcessor: NormalProcessor!
    
    override func setUp() {
        super.setUp()
        normalProcessor = try! NormalProcessor(device: device)
    }
    
    func testDegenerateTriangles() async throws {
        // Test handling of degenerate triangles (zero area)
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 0, 0)  // Degenerate triangle (repeated vertex)
        ]
        
        let indices: [UInt32] = [0, 1, 2]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        // Processor should handle degenerate triangles gracefully
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(handleDegenerates: true)
        )
        
        // Verify degenerate triangles are handled
        let normal = result.normals[0]
        XCTAssertFalse(normal.x.isNaN && normal.y.isNaN && normal.z.isNaN)
        XCTAssertEqual(length(normal), 1.0, accuracy: 1e-6)
    }
    
    func testNonManifoldEdges() async throws {
        // Test handling of non-manifold edges (edge shared by more than two triangles)
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),    // 0
            SIMD3(1, 0, 0),    // 1
            SIMD3(0, 1, 0),    // 2
            SIMD3(0, 0, 1),    // 3
            SIMD3(0, -1, 0)    // 4
        ]
        
        let indices: [UInt32] = [
            0, 1, 2,  // First triangle
            0, 1, 3,  // Second triangle sharing edge 0-1
            0, 1, 4   // Third triangle sharing edge 0-1 (non-manifold)
        ]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(handleNonManifold: true)
        )
        
        // Verify non-manifold edges are handled correctly
        for normal in result.normals {
            XCTAssertEqual(length(normal), 1.0, accuracy: 1e-6)
        }
        
        // Verify edge vertices have reasonable normals
        let edge0Normal = result.normals[0]
        let edge1Normal = result.normals[1]
        
        // Edge normals should be average of adjacent face normals
        XCTAssertGreaterThan(dot(edge0Normal, edge1Normal), 0)
    }
    
    func testDisconnectedComponents() async throws {
        // Test handling of meshes with multiple disconnected components
        let (component1, indices1) = generateCubeMesh(offset: SIMD3(0, 0, 0))
        let (component2, indices2) = generateCubeMesh(offset: SIMD3(3, 0, 0))
        
        let vertices = component1 + component2
        let indices = indices1 + indices2.map { $0 + UInt32(component1.count) }
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(handleDisconnected: true)
        )
        
        // Verify each component has correct normals
        for i in 0..<component1.count {
            XCTAssertEqual(length(result.normals[i]), 1.0, accuracy: 1e-6)
        }
        for i in component1.count..<vertices.count {
            XCTAssertEqual(length(result.normals[i]), 1.0, accuracy: 1e-6)
        }
    }
    
    func testSingularities() async throws {
        // Test handling of mesh singularities (vertices with invalid neighborhoods)
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),      // Singular vertex
            SIMD3(1, 0, 0),
            SIMD3(0, 1, 0),
            SIMD3(-1, 0, 0),
            SIMD3(0, -1, 0)
        ]
        
        let indices: [UInt32] = [
            0, 1, 2,
            0, 2, 3,
            0, 3, 4,
            0, 4, 1
        ]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(handleSingularities: true)
        )
        
        // Verify singular vertex normal
        let singularNormal = result.normals[0]
        XCTAssertEqual(length(singularNormal), 1.0, accuracy: 1e-6)
        XCTAssertEqual(singularNormal.z, 1.0, accuracy: 0.1)
    }
    
    func testBoundaryEdges() async throws {
        // Test handling of mesh boundaries
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),    // Boundary vertex
            SIMD3(1, 0, 0),    // Boundary vertex
            SIMD3(0, 1, 0),    // Interior vertex
            SIMD3(-1, 0, 0)    // Interior vertex
        ]
        
        let indices: [UInt32] = [
            0, 1, 2,  // Triangle with boundary edge 0-1
            0, 2, 3   // Adjacent triangle
        ]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(handleBoundaries: true)
        )
        
        // Verify boundary vertex normals
        for i in 0...1 {
            XCTAssertEqual(length(result.normals[i]), 1.0, accuracy: 1e-6)
        }
        
        // Verify boundary normals are reasonable
        let boundaryNormal = result.normals[0]
        XCTAssertGreaterThan(boundaryNormal.z, 0)
    }
    
    func testInvalidIndices() async throws {
        // Test handling of invalid vertex indices
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(0, 1, 0)
        ]
        
        let indices: [UInt32] = [
            0, 1, 2,
            0, 1, 5  // Invalid index
        ]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        do {
            _ = try await normalProcessor.recomputeNormals(mesh)
            XCTFail("Should throw error for invalid indices")
        } catch {
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    func testEmptyMesh() async throws {
        // Test handling of empty mesh
        let mesh = MeshData(
            vertices: [],
            indices: [],
            normals: [],
            confidence: [],
            metadata: MeshMetadata(source: .test)
        )
        
        do {
            _ = try await normalProcessor.recomputeNormals(mesh)
            XCTFail("Should throw error for empty mesh")
        } catch {
            XCTAssertTrue(error is ValidationError)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateCubeMesh(
        offset: SIMD3<Float>
    ) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        let vertices = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1),
            SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1),
            SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ].map { $0 + offset }
        
        let indices: [UInt32] = [
            0, 1, 2, 0, 2, 3,  // Front
            1, 5, 6, 1, 6, 2,  // Right
            5, 4, 7, 5, 7, 6,  // Back
            4, 0, 3, 4, 3, 7,  // Left
            3, 2, 6, 3, 6, 7,  // Top
            4, 5, 1, 4, 1, 0   // Bottom
        ]
        
        return (vertices, indices)
    }
}
