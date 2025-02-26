import XCTest
import Metal
@testable import xcalp

final class NormalRecomputationTests: MeshProcessingTestFixture {
    private var normalProcessor: NormalProcessor!
    
    override func setUp() {
        super.setUp()
        normalProcessor = try! NormalProcessor(device: device)
    }
    
    func testBasicRecomputation() async throws {
        // Test with a simple cube mesh where normals are known
        let vertices: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        
        let indices: [UInt32] = [
            0, 1, 2, 0, 2, 3,  // Front
            1, 5, 6, 1, 6, 2,  // Right
            5, 4, 7, 5, 7, 6,  // Back
            4, 0, 3, 4, 3, 7,  // Left
            3, 2, 6, 3, 6, 7,  // Top
            4, 5, 1, 4, 1, 0   // Bottom
        ]
        
        let mesh = MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(mesh)
        
        // Verify normals are unit length
        for normal in result.normals {
            XCTAssertEqual(length(normal), 1.0, accuracy: 1e-6)
        }
        
        // Verify expected normal directions for cube faces
        // Front face normals should point towards -z
        let frontNormal = result.normals[0]
        XCTAssertEqual(frontNormal.z, -1.0, accuracy: 0.1)
        
        // Right face normals should point towards +x
        let rightNormal = result.normals[1]
        XCTAssertEqual(rightNormal.x, 1.0, accuracy: 0.1)
    }
    
    func testNormalConsistency() async throws {
        // Test that adjacent faces produce consistent normals
        let vertices = generateTestSphere(radius: 1.0, segments: 16)
        let mesh = MeshData(
            vertices: vertices.vertices,
            indices: vertices.indices,
            normals: Array(repeating: .zero, count: vertices.vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(mesh)
        
        // Check normal consistency across adjacent faces
        for i in stride(from: 0, to: result.indices.count, by: 3) {
            let v1 = Int(result.indices[i])
            let v2 = Int(result.indices[i + 1])
            let v3 = Int(result.indices[i + 2])
            
            // Normals of adjacent vertices should be similar
            let angle12 = acos(dot(result.normals[v1], result.normals[v2]))
            let angle23 = acos(dot(result.normals[v2], result.normals[v3]))
            let angle31 = acos(dot(result.normals[v3], result.normals[v1]))
            
            XCTAssertLessThan(angle12, .pi / 4)
            XCTAssertLessThan(angle23, .pi / 4)
            XCTAssertLessThan(angle31, .pi / 4)
        }
    }
    
    func testSharpFeaturePreservation() async throws {
        // Test that sharp features are preserved during normal computation
        let vertices = generateCubeWithBevel()
        let mesh = MeshData(
            vertices: vertices.vertices,
            indices: vertices.indices,
            normals: Array(repeating: .zero, count: vertices.vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        let result = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(
                featureAngleThreshold: .pi / 6,
                smoothingIterations: 1,
                weightByArea: true
            )
        )
        
        // Verify sharp edges are preserved
        for (v1, v2, angle) in vertices.expectedFeatures {
            let computedAngle = acos(dot(result.normals[v1], result.normals[v2]))
            XCTAssertEqual(computedAngle, angle, accuracy: 0.1)
        }
    }
    
    func testWeightedNormals() async throws {
        // Test area-weighted normal computation
        let vertices = generateIrregularMesh()
        let mesh = MeshData(
            vertices: vertices.vertices,
            indices: vertices.indices,
            normals: Array(repeating: .zero, count: vertices.vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        // Compute with and without area weighting
        let unweightedResult = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(weightByArea: false)
        )
        
        let weightedResult = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(weightByArea: true)
        )
        
        // Verify that weighting affects the results
        var differences = 0
        for (unweighted, weighted) in zip(unweightedResult.normals, weightedResult.normals) {
            if length(unweighted - weighted) > 0.1 {
                differences += 1
            }
        }
        
        XCTAssertGreaterThan(differences, 0, "Area weighting had no effect")
    }
    
    func testParallelComputation() async throws {
        // Test parallel normal computation with a large mesh
        let vertices = generateLargeMesh(vertexCount: 100000)
        let mesh = MeshData(
            vertices: vertices.vertices,
            indices: vertices.indices,
            normals: Array(repeating: .zero, count: vertices.vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.vertices.count),
            metadata: MeshMetadata(source: .test)
        )
        
        // Measure sequential computation time
        let sequentialStart = CACurrentMediaTime()
        let sequentialResult = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(useParallelization: false)
        )
        let sequentialTime = CACurrentMediaTime() - sequentialStart
        
        // Measure parallel computation time
        let parallelStart = CACurrentMediaTime()
        let parallelResult = try await normalProcessor.recomputeNormals(
            mesh,
            options: .init(useParallelization: true)
        )
        let parallelTime = CACurrentMediaTime() - parallelStart
        
        // Verify results are equivalent
        for (seq, par) in zip(sequentialResult.normals, parallelResult.normals) {
            XCTAssertEqual(length(seq - par), 0, accuracy: 1e-6)
        }
        
        // Verify parallel computation is faster
        XCTAssertLessThan(parallelTime, sequentialTime)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestSphere(
        radius: Float,
        segments: Int
    ) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        for i in 0...segments {
            let phi = Float.pi * Float(i) / Float(segments)
            for j in 0...segments {
                let theta = 2 * Float.pi * Float(j) / Float(segments)
                
                let x = radius * sin(phi) * cos(theta)
                let y = radius * sin(phi) * sin(theta)
                let z = radius * cos(phi)
                
                vertices.append(SIMD3<Float>(x, y, z))
                
                if i < segments && j < segments {
                    let current = UInt32(i * (segments + 1) + j)
                    let next = current + 1
                    let bottom = current + UInt32(segments + 1)
                    let bottomNext = bottom + 1
                    
                    indices.append(contentsOf: [current, next, bottom])
                    indices.append(contentsOf: [next, bottomNext, bottom])
                }
            }
        }
        
        return (vertices, indices)
    }
    
    private func generateCubeWithBevel() -> (
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        expectedFeatures: [(Int, Int, Float)]
    ) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var expectedFeatures: [(Int, Int, Float)] = []
        
        // Add basic cube vertices
        let baseVertices = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        vertices.append(contentsOf: baseVertices)
        
        // Add beveled edges
        let bevelRadius: Float = 0.2
        for i in 0..<12 {
            let angle = Float(i) * .pi / 6
            let x = cos(angle) * bevelRadius
            let y = sin(angle) * bevelRadius
            vertices.append(SIMD3<Float>(x, y, 1))
            
            // Record expected feature angles
            expectedFeatures.append((
                vertices.count - 1,
                vertices.count - 2,
                .pi / 6
            ))
        }
        
        // Add face indices
        // Front face
        indices.append(contentsOf: [0, 1, 2, 0, 2, 3])
        // Add other faces...
        
        return (vertices, indices, expectedFeatures)
    }
    
    private func generateIrregularMesh() -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Generate irregular triangles
        for i in 0..<10 {
            let scale = Float(i + 1)
            vertices.append(SIMD3<Float>(
                Float.random(in: -scale...scale),
                Float.random(in: -scale...scale),
                Float.random(in: -scale...scale)
            ))
        }
        
        // Generate triangles with varying sizes
        for i in 0..<8 {
            indices.append(contentsOf: [
                UInt32(i),
                UInt32(i + 1),
                UInt32(i + 2)
            ])
        }
        
        return (vertices, indices)
    }
    
    private func generateLargeMesh(vertexCount: Int) -> (
        vertices: [SIMD3<Float>],
        indices: [UInt32]
    ) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Generate random vertices
        for _ in 0..<vertexCount {
            vertices.append(SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            ))
        }
        
        // Generate triangles
        for i in 0..<(vertexCount - 2) {
            if i % 3 == 0 {
                indices.append(contentsOf: [
                    UInt32(i),
                    UInt32(i + 1),
                    UInt32(i + 2)
                ])
            }
        }
        
        return (vertices, indices)
    }
}