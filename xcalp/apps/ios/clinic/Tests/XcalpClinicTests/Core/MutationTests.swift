import XCTest
import Metal
@testable import xcalp

final class MutationTests: MeshProcessingTestFixture {
    private var mutationEngine: MutationEngine!
    private let mutationCount = 100
    
    override func setUp() {
        super.setUp()
        mutationEngine = MutationEngine()
    }
    
    func testMutationSurvival() async throws {
        let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
        var detectedMutations = 0
        var totalMutations = 0
        
        // Test different mutation types
        for mutationType in MutationType.allCases {
            for _ in 0..<mutationCount {
                let mutation = mutationEngine.generateMutation(of: mutationType)
                let mutatedMesh = try mutation.apply(to: testMesh)
                
                do {
                    let processed = try await processMeshWithFullPipeline(mutatedMesh)
                    try validateProcessingResult(processed, original: testMesh)
                    
                    // If we get here without an error or quality difference,
                    // the mutation survived
                    print("Mutation survived: \(mutation)")
                } catch {
                    // Mutation was detected
                    detectedMutations += 1
                }
                totalMutations += 1
            }
        }
        
        // Calculate mutation score
        let mutationScore = Double(detectedMutations) / Double(totalMutations)
        XCTAssertGreaterThanOrEqual(
            mutationScore,
            0.85,
            "Mutation detection rate too low"
        )
    }
    
    func testMeshMutations() async throws {
        let testCases = [
            (TestMeshGenerator.MeshType.sphere, "sphere"),
            (TestMeshGenerator.MeshType.cube, "cube"),
            (TestMeshGenerator.MeshType.cylinder, "cylinder")
        ]
        
        for (meshType, name) in testCases {
            let testMesh = TestMeshGenerator.generateTestMesh(meshType)
            
            // Apply various mutations
            try await testVertexMutations(testMesh, name: name)
            try await testNormalMutations(testMesh, name: name)
            try await testTopologyMutations(testMesh, name: name)
            try await testConfidenceMutations(testMesh, name: name)
        }
    }
    
    private func testVertexMutations(_ mesh: MeshData, name: String) async throws {
        let mutations = [
            VertexTranslationMutation(offset: SIMD3<Float>(0.1, 0, 0)),
            VertexScaleMutation(scale: 1.5),
            VertexNoiseMutation(amplitude: 0.1)
        ]
        
        for mutation in mutations {
            let mutatedMesh = try mutation.apply(to: mesh)
            
            do {
                let processed = try await processMeshWithFullPipeline(mutatedMesh)
                try validateMutationResult(processed, original: mesh, mutation: mutation)
            } catch {
                XCTAssertTrue(error is ValidationError, "Unexpected error type")
            }
        }
    }
    
    private func testNormalMutations(_ mesh: MeshData, name: String) async throws {
        let mutations = [
            NormalFlipMutation(),
            NormalNoiseMutation(maxAngle: .pi / 4),
            NormalRandomizationMutation()
        ]
        
        for mutation in mutations {
            let mutatedMesh = try mutation.apply(to: mesh)
            
            do {
                let processed = try await processMeshWithFullPipeline(mutatedMesh)
                try validateMutationResult(processed, original: mesh, mutation: mutation)
            } catch {
                XCTAssertTrue(error is ValidationError, "Unexpected error type")
            }
        }
    }
    
    private func testTopologyMutations(_ mesh: MeshData, name: String) async throws {
        let mutations = [
            TriangleFlipMutation(),
            EdgeCollapseMutation(),
            VertexRemovalMutation()
        ]
        
        for mutation in mutations {
            let mutatedMesh = try mutation.apply(to: mesh)
            
            do {
                let processed = try await processMeshWithFullPipeline(mutatedMesh)
                try validateMutationResult(processed, original: mesh, mutation: mutation)
            } catch {
                XCTAssertTrue(error is ValidationError, "Unexpected error type")
            }
        }
    }
    
    private func testConfidenceMutations(_ mesh: MeshData, name: String) async throws {
        let mutations = [
            ConfidenceZeroMutation(),
            ConfidenceRandomizationMutation(),
            ConfidenceInversionMutation()
        ]
        
        for mutation in mutations {
            let mutatedMesh = try mutation.apply(to: mesh)
            
            do {
                let processed = try await processMeshWithFullPipeline(mutatedMesh)
                try validateMutationResult(processed, original: mesh, mutation: mutation)
            } catch {
                XCTAssertTrue(error is ValidationError, "Unexpected error type")
            }
        }
    }
    
    private func validateMutationResult(
        _ processed: MeshData,
        original: MeshData,
        mutation: Mutation
    ) throws {
        // Verify mesh integrity
        try validateMeshTopology(processed)
        
        // Check if mutation was handled appropriately
        if mutation.shouldBeDetected {
            // For mutations that should be detected and corrected
            try validateProcessingResult(processed, original: original)
        } else {
            // For benign mutations that should be preserved
            XCTAssertFalse(
                meshesAreIdentical(processed, original),
                "Mutation was incorrectly removed"
            )
        }
    }
    
    private func meshesAreIdentical(_ mesh1: MeshData, _ mesh2: MeshData) -> Bool {
        return mesh1.vertices == mesh2.vertices &&
               mesh1.normals == mesh2.normals &&
               mesh1.indices == mesh2.indices &&
               mesh1.confidence == mesh2.confidence
    }
}

// MARK: - Mutation Types

enum MutationType: CaseIterable {
    case vertexTranslation
    case vertexScale
    case vertexNoise
    case normalFlip
    case normalNoise
    case normalRandomization
    case triangleFlip
    case edgeCollapse
    case vertexRemoval
    case confidenceZero
    case confidenceRandomization
    case confidenceInversion
}

// MARK: - Mutation Protocol

protocol Mutation {
    var shouldBeDetected: Bool { get }
    func apply(to mesh: MeshData) throws -> MeshData
}

// MARK: - Vertex Mutations

struct VertexTranslationMutation: Mutation {
    let offset: SIMD3<Float>
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newVertices = mesh.vertices
        for i in 0..<newVertices.count {
            newVertices[i] += offset
        }
        return MeshData(
            vertices: newVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct VertexScaleMutation: Mutation {
    let scale: Float
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newVertices = mesh.vertices
        for i in 0..<newVertices.count {
            newVertices[i] *= scale
        }
        return MeshData(
            vertices: newVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct VertexNoiseMutation: Mutation {
    let amplitude: Float
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newVertices = mesh.vertices
        for i in 0..<newVertices.count {
            let noise = SIMD3<Float>(
                Float.random(in: -amplitude...amplitude),
                Float.random(in: -amplitude...amplitude),
                Float.random(in: -amplitude...amplitude)
            )
            newVertices[i] += noise
        }
        return MeshData(
            vertices: newVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

// MARK: - Normal Mutations

struct NormalFlipMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newNormals = mesh.normals
        for i in 0..<newNormals.count {
            newNormals[i] *= -1
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: newNormals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct NormalNoiseMutation: Mutation {
    let maxAngle: Float
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newNormals = mesh.normals
        for i in 0..<newNormals.count {
            let rotation = simd_quatf(angle: Float.random(in: -maxAngle...maxAngle),
                                    axis: normalize(SIMD3<Float>.random(in: -1...1)))
            newNormals[i] = rotation.act(newNormals[i])
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: newNormals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

// MARK: - Topology Mutations

struct TriangleFlipMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newIndices = mesh.indices
        for i in stride(from: 0, to: newIndices.count, by: 3) {
            swap(&newIndices[i], &newIndices[i + 1])
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: newIndices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

// MARK: - Confidence Mutations

struct ConfidenceZeroMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: Array(repeating: 0.0, count: mesh.confidence.count),
            metadata: mesh.metadata
        )
    }
}

// MARK: - Mutation Engine

class MutationEngine {
    func generateMutation(of type: MutationType) -> Mutation {
        switch type {
        case .vertexTranslation:
            return VertexTranslationMutation(
                offset: SIMD3<Float>(0.1, 0.1, 0.1)
            )
        case .vertexScale:
            return VertexScaleMutation(scale: 1.5)
        case .vertexNoise:
            return VertexNoiseMutation(amplitude: 0.1)
        case .normalFlip:
            return NormalFlipMutation()
        case .normalNoise:
            return NormalNoiseMutation(maxAngle: .pi / 4)
        case .normalRandomization:
            return NormalRandomizationMutation()
        case .triangleFlip:
            return TriangleFlipMutation()
        case .edgeCollapse:
            return EdgeCollapseSimulation()
        case .vertexRemoval:
            return VertexRemovalSimulation()
        case .confidenceZero:
            return ConfidenceZeroMutation()
        case .confidenceRandomization:
            return ConfidenceRandomizationMutation()
        case .confidenceInversion:
            return ConfidenceInversionMutation()
        }
    }
}

// Add remaining mutation implementations...
struct NormalRandomizationMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newNormals = [SIMD3<Float>](repeating: .zero, count: mesh.normals.count)
        for i in 0..<newNormals.count {
            newNormals[i] = normalize(SIMD3<Float>.random(in: -1...1))
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: newNormals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct EdgeCollapseSimulation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        // Simulate edge collapse by moving vertices closer together
        var newVertices = mesh.vertices
        for i in stride(from: 0, to: newVertices.count - 1, by: 2) {
            let midpoint = (newVertices[i] + newVertices[i + 1]) * 0.5
            newVertices[i] = midpoint
            newVertices[i + 1] = midpoint
        }
        return MeshData(
            vertices: newVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct VertexRemovalSimulation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        // Simulate vertex removal by setting random vertices to origin
        var newVertices = mesh.vertices
        for i in stride(from: 0, to: newVertices.count, by: 10) {
            newVertices[i] = .zero
        }
        return MeshData(
            vertices: newVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

struct ConfidenceRandomizationMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newConfidence = mesh.confidence
        for i in 0..<newConfidence.count {
            newConfidence[i] = Float.random(in: 0...1)
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: newConfidence,
            metadata: mesh.metadata
        )
    }
}

struct ConfidenceInversionMutation: Mutation {
    var shouldBeDetected: Bool { return true }
    
    func apply(to mesh: MeshData) throws -> MeshData {
        var newConfidence = mesh.confidence
        for i in 0..<newConfidence.count {
            newConfidence[i] = 1.0 - newConfidence[i]
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: newConfidence,
            metadata: mesh.metadata
        )
    }
}