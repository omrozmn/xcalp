import XCTest
import Metal
import simd
@testable import xcalp

final class MeshProcessingUnitTests: XCTestCase {
    private let device: MTLDevice
    private let epsilon: Float = 1e-6
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        try super.init()
    }
    
    // MARK: - Bilateral Filter Tests
    
    func testBilateralFilterBasicSmoothing() async throws {
        let filter = try BilateralMeshFilter(device: device)
        let testMesh = createSimpleNoisyMesh()
        
        let filtered = try await filter.filter(testMesh)
        
        // Verify smoothing effect
        for (original, filtered) in zip(testMesh.vertices, filtered.vertices) {
            let distance = length(original - filtered)
            XCTAssertLessThan(distance, 0.1, "Excessive smoothing detected")
        }
        
        // Verify normal preservation
        for (original, filtered) in zip(testMesh.normals, filtered.normals) {
            let dotProduct = abs(dot(normalize(original), normalize(filtered)))
            XCTAssertGreaterThan(dotProduct, 0.95, "Normal direction not preserved")
        }
    }
    
    func testBilateralFilterFeaturePreservation() async throws {
        let filter = try BilateralMeshFilter(device: device)
        let testMesh = createFeatureMesh()
        
        let filtered = try await filter.filter(
            testMesh,
            parameters: .init(
                spatialSigma: 0.01,
                normalSigma: 0.5,
                iterations: 3,
                featurePreservationWeight: 0.9
            )
        )
        
        // Verify feature edges are preserved
        let features = detectFeatures(filtered)
        XCTAssertGreaterThanOrEqual(
            features.count,
            detectFeatures(testMesh).count * 0.9,
            "Features were not preserved"
        )
    }
    
    // MARK: - Mesh Optimizer Tests
    
    func testMeshOptimizerVertexClustering() async throws {
        let optimizer = try MeshOptimizer()
        let testMesh = createRedundantMesh()
        
        let optimized = try await optimizer.optimizeMesh(testMesh)
        
        // Verify vertex reduction
        XCTAssertLessThan(
            optimized.vertices.count,
            testMesh.vertices.count,
            "No vertex reduction occurred"
        )
        
        // Verify topology preservation
        try XCTAssertMeshQuality(optimized)
    }
    
    func testMeshOptimizerTriangleQuality() async throws {
        let optimizer = try MeshOptimizer()
        let testMesh = createDegenerateMesh()
        
        let optimized = try await optimizer.optimizeMesh(testMesh)
        
        // Verify triangle quality improvement
        let originalQuality = calculateTriangleQualities(testMesh)
        let optimizedQuality = calculateTriangleQualities(optimized)
        
        XCTAssertGreaterThan(
            optimizedQuality.min() ?? 0,
            originalQuality.min() ?? 0,
            "Triangle quality not improved"
        )
    }
    
    // MARK: - Quality Analyzer Tests
    
    func testQualityAnalyzerMetrics() async throws {
        let analyzer = try MeshQualityAnalyzer(device: device)
        let testMesh = createTestMesh()
        
        let metrics = try await analyzer.analyzeMesh(testMesh)
        
        // Verify metric bounds
        XCTAssertGreaterThanOrEqual(metrics.pointDensity, 0)
        XCTAssertLessThanOrEqual(metrics.surfaceCompleteness, 1.0)
        XCTAssertGreaterThanOrEqual(metrics.noiseLevel, 0)
        XCTAssertLessThanOrEqual(metrics.featurePreservation, 1.0)
    }
    
    func testQualityAnalyzerConsistency() async throws {
        let analyzer = try MeshQualityAnalyzer(device: device)
        let testMesh = createTestMesh()
        
        // Test consistency across multiple analyses
        let firstMetrics = try await analyzer.analyzeMesh(testMesh)
        let secondMetrics = try await analyzer.analyzeMesh(testMesh)
        
        XCTAssertEqual(
            firstMetrics.pointDensity,
            secondMetrics.pointDensity,
            accuracy: epsilon
        )
        XCTAssertEqual(
            firstMetrics.surfaceCompleteness,
            secondMetrics.surfaceCompleteness,
            accuracy: epsilon
        )
    }
    
    // MARK: - Helper Methods
    
    private func createSimpleNoisyMesh() -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Create a noisy plane
        for i in 0...10 {
            for j in 0...10 {
                let x = Float(i) / 10.0
                let z = Float(j) / 10.0
                let y = Float.random(in: -0.05...0.05) // Noise
                
                vertices.append(SIMD3<Float>(x, y, z))
                normals.append(SIMD3<Float>(0, 1, 0))
                confidence.append(1.0)
                
                if i < 10 && j < 10 {
                    let current = UInt32(i * 11 + j)
                    indices.append(current)
                    indices.append(current + 1)
                    indices.append(current + 11)
                    
                    indices.append(current + 1)
                    indices.append(current + 12)
                    indices.append(current + 11)
                }
            }
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func createFeatureMesh() -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Create a cube with sharp edges
        let cubeVertices: [SIMD3<Float>] = [
            SIMD3<Float>(-1, -1, -1),
            SIMD3<Float>(1, -1, -1),
            SIMD3<Float>(1, 1, -1),
            SIMD3<Float>(-1, 1, -1),
            SIMD3<Float>(-1, -1, 1),
            SIMD3<Float>(1, -1, 1),
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(-1, 1, 1)
        ]
        
        let cubeNormals: [SIMD3<Float>] = [
            SIMD3<Float>(-1, -1, -1),
            SIMD3<Float>(1, -1, -1),
            SIMD3<Float>(1, 1, -1),
            SIMD3<Float>(-1, 1, -1),
            SIMD3<Float>(-1, -1, 1),
            SIMD3<Float>(1, -1, 1),
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(-1, 1, 1)
        ].map { normalize($0) }
        
        let cubeIndices: [UInt32] = [
            0, 1, 2, 0, 2, 3,  // Front
            1, 5, 6, 1, 6, 2,  // Right
            5, 4, 7, 5, 7, 6,  // Back
            4, 0, 3, 4, 3, 7,  // Left
            3, 2, 6, 3, 6, 7,  // Top
            4, 5, 1, 4, 1, 0   // Bottom
        ]
        
        vertices = cubeVertices
        normals = cubeNormals
        indices = cubeIndices
        confidence = Array(repeating: 1.0, count: vertices.count)
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func detectFeatures(_ mesh: MeshData) -> [(Int, Int)] {
        var features: [(Int, Int)] = []
        
        // Detect edges with high dihedral angles
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.normals[Int(mesh.indices[i])]
            let v2 = mesh.normals[Int(mesh.indices[i + 1])]
            
            let angle = acos(dot(v1, v2))
            if angle > Float.pi / 4 { // 45 degrees
                features.append((Int(mesh.indices[i]), Int(mesh.indices[i + 1])))
            }
        }
        
        return features
    }
    
    private func calculateTriangleQualities(_ mesh: MeshData) -> [Float] {
        var qualities: [Float] = []
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            // Calculate triangle quality (aspect ratio)
            let e1 = v2 - v1
            let e2 = v3 - v1
            let e3 = v3 - v2
            
            let area = length(cross(e1, e2)) * 0.5
            let perimeter = length(e1) + length(e2) + length(e3)
            
            qualities.append(4.0 * sqrt(3.0) * area / (perimeter * perimeter))
        }
        
        return qualities
    }
    
    private func createRedundantMesh() -> MeshData {
        // Create mesh with redundant vertices
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Add redundant vertices
        for _ in 0..<100 {
            let pos = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            vertices.append(pos)
            vertices.append(pos) // Duplicate
            
            let normal = normalize(SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            ))
            normals.append(normal)
            normals.append(normal)
            
            confidence.append(1.0)
            confidence.append(1.0)
        }
        
        // Create random triangles
        for i in stride(from: 0, to: vertices.count - 2, by: 3) {
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func createDegenerateMesh() -> MeshData {
        // Create mesh with some degenerate triangles
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Add vertices including some very close together
        for i in 0..<10 {
            let basePos = SIMD3<Float>(
                Float(i) / 10.0,
                0,
                0
            )
            vertices.append(basePos)
            vertices.append(basePos + SIMD3<Float>(0.001, 0, 0)) // Nearly coincident
            vertices.append(basePos + SIMD3<Float>(0, 1, 0))
            
            let normal = SIMD3<Float>(0, 0, 1)
            normals.append(normal)
            normals.append(normal)
            normals.append(normal)
            
            confidence.append(contentsOf: [1.0, 1.0, 1.0])
            
            // Create degenerate triangle
            indices.append(UInt32(i * 3))
            indices.append(UInt32(i * 3 + 1))
            indices.append(UInt32(i * 3 + 2))
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func createTestMesh() -> MeshData {
        // Create a simple test mesh (sphere)
        return TestMeshGenerator.generateTestMesh(.sphere)
    }
}