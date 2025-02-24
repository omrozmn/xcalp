@testable import XcalpClinic
import Metal
import XCTest

final class MeshProcessorTests: XCTestCase {
    private var meshProcessor: MeshProcessor?
    
    override func setUp() async throws {
        try await super.setUp()
        meshProcessor = try MeshProcessor()
    }
    
    override func tearDown() async throws {
        meshProcessor = nil
        try await super.tearDown()
    }
    
    // MARK: - Input Validation Tests
    
    func testInvalidInputData() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        // Test with empty point cloud
        await assertThrowsError(
            try await processor.processPointCloud(
                [],
                photogrammetryData: nil,
                quality: .medium
            )
        ) { error in
            guard case MeshProcessingError.invalidInputData = error else {
                XCTFail("Expected invalidInputData error")
                return
            }
        }
    }
    
    func testInsufficientFeatures() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let photogrammetryData = MockPhotogrammetryData(
            features: Array(repeating: MockFeature(), count: ClinicalConstants.minPhotogrammetryFeatures - 1)
        )
        
        await assertThrowsError(
            try await processor.processPointCloud(
                [.zero],
                photogrammetryData: photogrammetryData,
                quality: .medium
            )
        ) { error in
            guard case MeshProcessingError.insufficientFeatures = error else {
                XCTFail("Expected insufficientFeatures error")
                return
            }
        }
    }
    
    // MARK: - Quality Validation Tests
    
    func testMeshQualityValidation() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let testMesh = createTestMesh(vertexCount: 10000, quality: .good)
        let processedMesh = try await processor.processPointCloud(
            testMesh.vertices,
            photogrammetryData: nil,
            quality: .high
        )
        
        // Verify mesh meets quality requirements
        let metrics = try XCTUnwrap(processedMesh.getMeshMetrics())
        XCTAssertGreaterThanOrEqual(metrics.vertexDensity, ClinicalConstants.minimumPointDensity)
        XCTAssertGreaterThanOrEqual(metrics.normalConsistency, ClinicalConstants.minimumNormalConsistency)
        XCTAssertGreaterThanOrEqual(metrics.surfaceSmoothness, ClinicalConstants.minimumSurfaceSmoothness)
    }
    
    func testPoorQualityMesh() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let testMesh = createTestMesh(vertexCount: 100, quality: .poor)
        
        await assertThrowsError(
            try await processor.processPointCloud(
                testMesh.vertices,
                photogrammetryData: nil,
                quality: .high
            )
        ) { error in
            guard case MeshProcessingError.qualityValidationFailed = error else {
                XCTFail("Expected qualityValidationFailed error")
                return
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testProcessingPerformance() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let testMesh = createTestMesh(vertexCount: 100000, quality: .good)
        
        measure {
            let expectation = expectation(description: "Mesh Processing")
            
            Task {
                do {
                    let startTime = CACurrentMediaTime()
                    _ = try await processor.processPointCloud(
                        testMesh.vertices,
                        photogrammetryData: nil,
                        quality: .medium
                    )
                    let duration = CACurrentMediaTime() - startTime
                    
                    // Should process within reasonable time
                    XCTAssertLessThan(duration, 5.0)
                    expectation.fulfill()
                } catch {
                    XCTFail("Processing failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Metal Integration Tests
    
    func testGPUAcceleration() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let testMesh = createTestMesh(vertexCount: 50000, quality: .good)
        
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is not supported on this device")
        }
        
        let processedMesh = try await processor.processPointCloud(
            testMesh.vertices,
            photogrammetryData: nil,
            quality: .high
        )
        XCTAssertNotNil(processedMesh, "GPU-accelerated processing should succeed")
    }
    
    // MARK: - Feature Preservation Tests
    
    func testFeaturePreservation() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let testMesh = createTestMesh(vertexCount: 1000, withFeatures: true)
        
        // Process mesh while preserving features
        let processedMesh = try await processor.processPointCloud(
            testMesh.vertices,
            photogrammetryData: nil,
            quality: .high
        )
        
        // Verify feature preservation
        XCTAssertGreaterThanOrEqual(
            processedMesh.getMeshMetrics().featurePreservation,
            ClinicalConstants.featurePreservationThreshold,
            "Features should be preserved above threshold"
        )
    }
    
    func testAdaptiveProcessing() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        // Test with different quality settings
        let testCases = [
            (MeshQuality.low, 8),
            (MeshQuality.medium, 10),
            (MeshQuality.high, 12)
        ]
        
        for (quality, expectedDepth) in testCases {
            let testMesh = createTestMesh(vertexCount: 5000, quality: .good)
            let processedMesh = try await processor.processPointCloud(
                testMesh.vertices,
                photogrammetryData: nil,
                quality: quality
            )
            
            let metrics = processedMesh.getMeshMetrics()
            XCTAssertGreaterThanOrEqual(metrics.vertexDensity, ClinicalConstants.minimumPointDensity)
            XCTAssertGreaterThanOrEqual(metrics.normalConsistency, ClinicalConstants.minimumNormalConsistency)
            XCTAssertGreaterThanOrEqual(metrics.surfaceSmoothness, ClinicalConstants.minimumSurfaceSmoothness)
        }
    }
    
    func testPerformanceOptimization() async throws {
        guard let processor = meshProcessor else {
            XCTFail("Processor not initialized")
            return
        }
        
        let largeTestMesh = createTestMesh(vertexCount: 100000, quality: .good)
        
        measure {
            let expectation = expectation(description: "Performance Test")
            
            Task {
                do {
                    let startTime = CACurrentMediaTime()
                    _ = try await processor.processPointCloud(
                        largeTestMesh.vertices,
                        photogrammetryData: nil,
                        quality: .medium
                    )
                    let duration = CACurrentMediaTime() - startTime
                    
                    XCTAssertLessThan(duration, 5.0, "Processing should complete within 5 seconds")
                    expectation.fulfill()
                } catch {
                    XCTFail("Processing failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestMesh(
        vertexCount: Int,
        withFeatures: Bool = false,
        quality: MeshQuality = .good
    ) -> MockMesh {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        
        // Create vertices with distinctive features if requested
        if withFeatures {
            // Add base mesh points
            for vertexIndex in 0..<vertexCount {
                let phi = acos(-1.0 + 2.0 * Float(vertexIndex) / Float(vertexCount))
                let theta = Float.pi * (1 + 5.0.squareRoot()) * Float(vertexIndex)
                
                let xCoord = cos(theta) * sin(phi)
                let yCoord = sin(theta) * sin(phi)
                let zCoord = cos(phi)
                
                vertices.append(SIMD3(xCoord, yCoord, zCoord))
                normals.append(normalize(SIMD3(xCoord, yCoord, zCoord)))
            }
            
            // Add distinctive features (sharp edges, corners)
            let featureCount = vertexCount / 10
            for i in 0..<featureCount {
                let angle = 2 * Float.pi * Float(i) / Float(featureCount)
                let feature = SIMD3(cos(angle), sin(angle), 1.0)
                vertices.append(feature)
                normals.append(normalize(feature))
            }
        } else {
            // Create simple spherical distribution
            for vertexIndex in 0..<vertexCount {
                let phi = acos(-1.0 + 2.0 * Float(vertexIndex) / Float(vertexCount))
                let theta = Float.pi * (1 + 5.0.squareRoot()) * Float(vertexIndex)
                
                let xCoord = cos(theta) * sin(phi)
                let yCoord = sin(theta) * sin(phi)
                let zCoord = cos(phi)
                
                vertices.append(SIMD3(xCoord, yCoord, zCoord))
                normals.append(normalize(SIMD3(xCoord, yCoord, zCoord)))
            }
        }
        
        return MockMesh(vertices: vertices, normals: normals)
    }
}

// MARK: - Mock Types

struct MockMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
}

struct MockPhotogrammetryData: PhotogrammetryData {
    let features: [Feature]
    var cameraParameters: CameraParameters = .init()
}

struct MockFeature: Feature {
    var position: SIMD3<Float> = .zero
    var confidence: Float = 1.0
}

enum MeshQuality {
    case poor, good
}