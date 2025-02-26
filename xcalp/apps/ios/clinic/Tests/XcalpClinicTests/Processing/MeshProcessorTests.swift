import XCTest
import ARKit
@testable import XcalpClinic

final class MeshProcessorTests: XCTestCase {
    var meshProcessor: MeshProcessor!
    
    override func setUp() {
        super.setUp()
        meshProcessor = MeshProcessor()
    }
    
    override func tearDown() {
        meshProcessor = nil
        super.tearDown()
    }
    
    func testPointCloudDensityValidation() throws {
        // Given
        let points = createSamplePointCloud(density: MeshProcessingConfig.minimumPointDensity - 100)
        
        // When/Then
        XCTAssertThrowsError(try meshProcessor.processPointCloud(points, scanID: UUID())) { error in
            XCTAssertTrue(error is MeshProcessingError)
            if case let MeshProcessingError.insufficientPointDensity(density) = error {
                XCTAssertEqual(density, MeshProcessingConfig.minimumPointDensity - 100, accuracy: 0.01)
            }
        }
    }
    
    func testSuccessfulMeshGeneration() throws {
        // Given
        let points = createSamplePointCloud(density: MeshProcessingConfig.minimumPointDensity + 100)
        
        // When
        let mesh = try meshProcessor.processPointCloud(points, scanID: UUID())
        
        // Then
        XCTAssertNotNil(mesh)
    }
    
    func testQualityValidation() throws {
        // Given
        let points = createSamplePointCloud(density: MeshProcessingConfig.minimumPointDensity + 100)
        
        // When
        let mesh = try meshProcessor.processPointCloud(points, scanID: UUID())
        
        // Then
        XCTAssertGreaterThanOrEqual(meshProcessor.validateMeshQuality(mesh), MeshProcessingConfig.featurePreservationThreshold)
    }
    
    // Helper functions
    private func createSamplePointCloud(density: Float) -> [simd_float3] {
        // Create a sample point cloud for testing
        // This is a mock implementation - replace with actual test data
        let numPoints = Int(density)
        var points = [simd_float3]()
        for _ in 0..<numPoints {
            points.append(simd_float3(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)))
        }
        return points
    }
}
