import XCTest
import Metal
import simd
@testable import xcalp

final class FuzzingTests: MeshProcessingTestFixture {
    private let fuzzer: MeshFuzzer
    private let iterationCount = 1000
    private let timeout: TimeInterval = 30
    
    override init() throws {
        self.fuzzer = MeshFuzzer()
        try super.init()
    }
    
    func testRandomizedInputs() async throws {
        var successCount = 0
        var validationErrors = 0
        var processingErrors = 0
        var recoveryAttempts = 0
        
        for i in 0..<iterationCount {
            let fuzzedMesh = fuzzer.generateFuzzedMesh(complexity: .random)
            
            do {
                let startTime = CACurrentMediaTime()
                let result = try await processMeshWithTimeout(fuzzedMesh)
                
                if CACurrentMediaTime() - startTime > timeout {
                    throw ProcessingError.timeoutExceeded
                }
                
                // Verify result validity
                if try validateProcessedResult(result) {
                    successCount += 1
                }
            } catch is ValidationError {
                validationErrors += 1
            } catch is ProcessingError {
                processingErrors += 1
            } catch {
                // Attempt recovery
                do {
                    recoveryAttempts += 1
                    let recovered = try await recoverFromError(error, mesh: fuzzedMesh)
                    if try validateProcessedResult(recovered) {
                        successCount += 1
                    }
                } catch {
                    processingErrors += 1
                }
            }
            
            if i % 100 == 0 {
                print("Fuzzing progress: \(i)/\(iterationCount)")
                print("Success rate: \(Double(successCount) / Double(i + 1) * 100)%")
            }
        }
        
        // Report fuzzing results
        XCTAssertGreaterThan(Double(successCount) / Double(iterationCount), 0.8)
        print("""
        Fuzzing Results:
        Total iterations: \(iterationCount)
        Successful: \(successCount)
        Validation errors: \(validationErrors)
        Processing errors: \(processingErrors)
        Recovery attempts: \(recoveryAttempts)
        """)
    }
    
    func testMalformedGeometry() async throws {
        let malformations: [MalformationType] = [
            .invalidIndices,
            .degenerateTriangles,
            .disconnectedComponents,
            .nonManifoldEdges,
            .selfIntersections
        ]
        
        for malformation in malformations {
            let fuzzedMesh = fuzzer.generateMalformedMesh(type: malformation)
            
            do {
                let result = try await processMeshWithFullPipeline(fuzzedMesh)
                try validateMalformationHandling(result, type: malformation)
            } catch {
                XCTAssertTrue(error is ValidationError, "Unexpected error type")
            }
        }
    }
    
    func testBoundaryConditions() async throws {
        let boundaryTests = [
            BoundaryTest(name: "Empty Mesh", mesh: fuzzer.generateEmptyMesh()),
            BoundaryTest(name: "Single Triangle", mesh: fuzzer.generateMinimalMesh()),
            BoundaryTest(name: "Huge Mesh", mesh: fuzzer.generateHugeMesh()),
            BoundaryTest(name: "Zero-Area Triangles", mesh: fuzzer.generateDegenerateMesh()),
            BoundaryTest(name: "Invalid Normals", mesh: fuzzer.generateInvalidNormalsMesh())
        ]
        
        for test in boundaryTests {
            do {
                let result = try await processMeshWithFullPipeline(test.mesh)
                try validateBoundaryCase(result, test: test)
            } catch {
                handleBoundaryError(error, test: test)
            }
        }
    }
    
    func testFuzzedAttributes() async throws {
        let attributeFuzzers: [AttributeFuzzer] = [
            ConfidenceFuzzer(),
            NormalFuzzer(),
            IndexFuzzer(),
            MetadataFuzzer()
        ]
        
        for fuzzer in attributeFuzzers {
            let baseMesh = TestMeshGenerator.generateTestMesh(.sphere)
            let fuzzedMesh = fuzzer.fuzzAttributes(baseMesh)
            
            do {
                let result = try await processMeshWithFullPipeline(fuzzedMesh)
                try validateAttributeHandling(result, fuzzer: fuzzer)
            } catch {
                XCTAssertTrue(
                    fuzzer.isExpectedError(error),
                    "Unexpected error for \(type(of: fuzzer))"
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func processMeshWithTimeout(_ mesh: MeshData) async throws -> MeshData {
        return try await withTimeout(timeout) {
            try await self.processMeshWithFullPipeline(mesh)
        }
    }
    
    private func validateProcessedResult(_ mesh: MeshData) throws -> Bool {
        // Basic topology validation
        let topology = try MeshValidation.validateTopology(mesh)
        guard topology.isManifold else { return false }
        
        // Quality metrics validation
        let quality = try qualityAnalyzer.analyzeMesh(mesh)
        guard quality.surfaceCompleteness > 0.5 else { return false }
        
        return true
    }
    
    private func validateMalformationHandling(
        _ result: MeshData,
        type: MalformationType
    ) throws {
        switch type {
        case .invalidIndices:
            XCTAssertTrue(validateIndices(result))
        case .degenerateTriangles:
            XCTAssertTrue(validateTriangleQuality(result))
        case .disconnectedComponents:
            XCTAssertTrue(validateConnectivity(result))
        case .nonManifoldEdges:
            XCTAssertTrue(validateManifoldProperty(result))
        case .selfIntersections:
            XCTAssertTrue(validateNoIntersections(result))
        }
    }
    
    private func validateBoundaryCase(_ result: MeshData, test: BoundaryTest) throws {
        switch test.name {
        case "Empty Mesh":
            XCTAssertGreaterThan(result.vertices.count, 0)
        case "Single Triangle":
            try validateMinimalMesh(result)
        case "Huge Mesh":
            try validateLargeMeshHandling(result)
        case "Zero-Area Triangles":
            try validateNoDegenerateTriangles(result)
        case "Invalid Normals":
            try validateNormalCorrection(result)
        default:
            break
        }
    }
    
    private func validateAttributeHandling(
        _ result: MeshData,
        fuzzer: AttributeFuzzer
    ) throws {
        XCTAssertTrue(fuzzer.validateResult(result))
    }
    
    private func handleBoundaryError(_ error: Error, test: BoundaryTest) {
        switch test.name {
        case "Empty Mesh":
            XCTAssertTrue(error is ValidationError)
        case "Huge Mesh":
            XCTAssertTrue(error is OutOfMemoryError)
        default:
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Support Types

enum MalformationType {
    case invalidIndices
    case degenerateTriangles
    case disconnectedComponents
    case nonManifoldEdges
    case selfIntersections
}

struct BoundaryTest {
    let name: String
    let mesh: MeshData
}

protocol AttributeFuzzer {
    func fuzzAttributes(_ mesh: MeshData) -> MeshData
    func validateResult(_ mesh: MeshData) -> Bool
    func isExpectedError(_ error: Error) -> Bool
}

class MeshFuzzer {
    enum Complexity {
        case minimal
        case normal
        case extreme
        case random
        
        static func random() -> Complexity {
            let cases: [Complexity] = [.minimal, .normal, .extreme]
            return cases.randomElement() ?? .normal
        }
    }
    
    func generateFuzzedMesh(complexity: Complexity) -> MeshData {
        switch complexity {
        case .minimal:
            return generateMinimalMesh()
        case .normal:
            return generateRandomMesh()
        case .extreme:
            return generateExtremeMesh()
        case .random:
            return generateRandomMesh()
        }
    }
    
    func generateMalformedMesh(type: MalformationType) -> MeshData {
        switch type {
        case .invalidIndices:
            return generateInvalidIndicesMesh()
        case .degenerateTriangles:
            return generateDegenerateMesh()
        case .disconnectedComponents:
            return generateDisconnectedMesh()
        case .nonManifoldEdges:
            return generateNonManifoldMesh()
        case .selfIntersections:
            return generateSelfIntersectingMesh()
        }
    }
    
    func generateEmptyMesh() -> MeshData {
        return MeshData(
            vertices: [],
            indices: [],
            normals: [],
            confidence: [],
            metadata: MeshMetadata(source: .test)
        )
    }
    
    func generateMinimalMesh() -> MeshData {
        return MeshData(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            indices: [0, 1, 2],
            normals: [
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 0, 1)
            ],
            confidence: [1.0, 1.0, 1.0],
            metadata: MeshMetadata(source: .test)
        )
    }
    
    func generateHugeMesh() -> MeshData {
        return TestMeshGenerator.generateTestMesh(.sphere, resolution: 1024)
    }
    
    func generateInvalidNormalsMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Set some normals to zero
        for i in stride(from: 0, to: mesh.normals.count, by: 2) {
            mesh.normals[i] = .zero
        }
        return mesh
    }
    
    private func generateRandomMesh() -> MeshData {
        let vertexCount = Int.random(in: 10...1000)
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Generate random vertices
        for _ in 0..<vertexCount {
            vertices.append(SIMD3<Float>.random(in: -1...1))
            normals.append(normalize(SIMD3<Float>.random(in: -1...1)))
            confidence.append(Float.random(in: 0...1))
        }
        
        // Generate random triangles
        let triangleCount = vertexCount / 3
        for _ in 0..<triangleCount {
            indices.append(contentsOf: [
                UInt32.random(in: 0..<UInt32(vertexCount)),
                UInt32.random(in: 0..<UInt32(vertexCount)),
                UInt32.random(in: 0..<UInt32(vertexCount))
            ])
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func generateExtremeMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Add extreme values
        mesh.vertices.append(SIMD3<Float>(Float.infinity, 0, 0))
        mesh.vertices.append(SIMD3<Float>(-Float.infinity, 0, 0))
        mesh.vertices.append(SIMD3<Float>(Float.nan, 0, 0))
        return mesh
    }
    
    private func generateInvalidIndicesMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Add out-of-bounds indices
        mesh.indices.append(UInt32(mesh.vertices.count + 1))
        return mesh
    }
    
    private func generateDegenerateMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Make some triangles degenerate
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            mesh.vertices[Int(mesh.indices[i])] = mesh.vertices[Int(mesh.indices[i + 1])]
        }
        return mesh
    }
    
    private func generateDisconnectedMesh() -> MeshData {
        // Create two separate mesh components
        let mesh1 = generateRandomMesh()
        var mesh2 = generateRandomMesh()
        
        // Offset second mesh
        for i in 0..<mesh2.vertices.count {
            mesh2.vertices[i] += SIMD3<Float>(10, 10, 10)
        }
        
        // Combine meshes
        return MeshData(
            vertices: mesh1.vertices + mesh2.vertices,
            indices: mesh1.indices + mesh2.indices.map { $0 + UInt32(mesh1.vertices.count) },
            normals: mesh1.normals + mesh2.normals,
            confidence: mesh1.confidence + mesh2.confidence,
            metadata: mesh1.metadata
        )
    }
    
    private func generateNonManifoldMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Create non-manifold edge by sharing an edge between more than two triangles
        if mesh.vertices.count >= 4 {
            mesh.indices.append(contentsOf: [0, 1, 3])
            mesh.indices.append(contentsOf: [0, 1, 2])
        }
        return mesh
    }
    
    private func generateSelfIntersectingMesh() -> MeshData {
        var mesh = generateRandomMesh()
        // Create self-intersecting triangles
        if mesh.vertices.count >= 6 {
            let v1 = SIMD3<Float>(0, 0, 0)
            let v2 = SIMD3<Float>(1, 0, 0)
            let v3 = SIMD3<Float>(0, 1, 0)
            let v4 = SIMD3<Float>(0.5, 0.5, -1)
            let v5 = SIMD3<Float>(0.5, 0.5, 1)
            
            mesh.vertices.append(contentsOf: [v1, v2, v3, v4, v5])
            let baseIndex = UInt32(mesh.vertices.count - 5)
            mesh.indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex + 3, baseIndex + 4, baseIndex + 2
            ])
        }
        return mesh
    }
}

// MARK: - Attribute Fuzzers

class ConfidenceFuzzer: AttributeFuzzer {
    func fuzzAttributes(_ mesh: MeshData) -> MeshData {
        var confidence = mesh.confidence
        for i in 0..<confidence.count {
            confidence[i] = Float.random(in: -1...2) // Invalid range
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: confidence,
            metadata: mesh.metadata
        )
    }
    
    func validateResult(_ mesh: MeshData) -> Bool {
        return mesh.confidence.allSatisfy { $0 >= 0 && $0 <= 1 }
    }
    
    func isExpectedError(_ error: Error) -> Bool {
        return error is ValidationError
    }
}

class NormalFuzzer: AttributeFuzzer {
    func fuzzAttributes(_ mesh: MeshData) -> MeshData {
        var normals = mesh.normals
        for i in 0..<normals.count {
            // Generate invalid normals
            normals[i] = SIMD3<Float>(
                Float.random(in: -10...10),
                Float.random(in: -10...10),
                Float.random(in: -10...10)
            )
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
    
    func validateResult(_ mesh: MeshData) -> Bool {
        return mesh.normals.allSatisfy { abs(length($0) - 1) < 1e-6 }
    }
    
    func isExpectedError(_ error: Error) -> Bool {
        return error is ValidationError
    }
}

class IndexFuzzer: AttributeFuzzer {
    func fuzzAttributes(_ mesh: MeshData) -> MeshData {
        var indices = mesh.indices
        for i in 0..<indices.count {
            indices[i] = UInt32.random(in: 0...UInt32.max)
        }
        return MeshData(
            vertices: mesh.vertices,
            indices: indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
    
    func validateResult(_ mesh: MeshData) -> Bool {
        return mesh.indices.allSatisfy { $0 < mesh.vertices.count }
    }
    
    func isExpectedError(_ error: Error) -> Bool {
        return error is ValidationError
    }
}

class MetadataFuzzer: AttributeFuzzer {
    func fuzzAttributes(_ mesh: MeshData) -> MeshData {
        var metadata = mesh.metadata
        metadata.source = .test
        metadata.timestamp = Date.distantPast
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: metadata
        )
    }
    
    func validateResult(_ mesh: MeshData) -> Bool {
        return mesh.metadata.timestamp > Date.distantPast
    }
    
    func isExpectedError(_ error: Error) -> Bool {
        return error is ValidationError
    }
}