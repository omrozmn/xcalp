import XCTest
@testable import XcalpClinic

final class CulturalPatternAnalyzerTests: XCTestCase {
    var analyzer: CulturalPatternAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = CulturalPatternAnalyzer.shared
    }
    
    func testEastAsianPatternAnalysis() async throws {
        // Given
        let scanData = createTestScanData(
            angle: 85.0,
            density: 75.0,
            pattern: .straight,
            texture: TextureMetrics(
                coarseness: 0.7,
                waviness: 0.2,
                direction: .vertical
            )
        )
        
        // When
        let result = try await analyzer.analyzeHairPattern(scanData)
        
        // Then
        XCTAssertEqual(result.region, .eastAsia)
        XCTAssertGreaterThanOrEqual(result.conformanceScore, 0.9)
        XCTAssertEqual(result.actualMetrics.pattern, .straight)
    }
    
    func testAfricanDescentPatternAnalysis() async throws {
        // Given
        let scanData = createTestScanData(
            angle: 45.0,
            density: 90.0,
            pattern: .coiled,
            texture: TextureMetrics(
                coarseness: 0.9,
                waviness: 0.9,
                direction: .spiral
            )
        )
        
        // When
        let result = try await analyzer.analyzeHairPattern(scanData)
        
        // Then
        XCTAssertEqual(result.region, .africanDescent)
        XCTAssertGreaterThanOrEqual(result.conformanceScore, 0.9)
        XCTAssertEqual(result.actualMetrics.pattern, .coiled)
    }
    
    func testMediterraneanPatternAnalysis() async throws {
        // Given
        let scanData = createTestScanData(
            angle: 65.0,
            density: 80.0,
            pattern: .wavy,
            texture: TextureMetrics(
                coarseness: 0.6,
                waviness: 0.7,
                direction: .variable
            )
        )
        
        // When
        let result = try await analyzer.analyzeHairPattern(scanData)
        
        // Then
        XCTAssertEqual(result.region, .mediterranean)
        XCTAssertGreaterThanOrEqual(result.conformanceScore, 0.9)
        XCTAssertEqual(result.actualMetrics.pattern, .wavy)
    }
    
    func testCrossRegionalAnalysis() async throws {
        // Test analysis of patterns that don't match regional expectations
        let scanData = createTestScanData(
            angle: 85.0, // East Asian angle
            density: 90.0, // African descent density
            pattern: .wavy, // Mediterranean pattern
            texture: TextureMetrics(
                coarseness: 0.7,
                waviness: 0.6,
                direction: .multidirectional
            )
        )
        
        let result = try await analyzer.analyzeHairPattern(scanData)
        
        // Should identify mixed characteristics
        XCTAssertLessThan(result.conformanceScore, 0.8)
    }
    
    // MARK: - Helper Methods
    
    private func createTestScanData(
        angle: Float,
        density: Float,
        pattern: GrowthPattern,
        texture: TextureMetrics
    ) -> ScanData {
        // Create test scan data with specified characteristics
        return ScanData(
            id: UUID(),
            mesh: createTestMesh(angle: angle),
            pointCloud: createTestPointCloud(density: density),
            metadata: createTestMetadata(pattern: pattern, texture: texture)
        )
    }
    
    private func createTestMesh(angle: Float) -> MeshData {
        // Implementation to create test mesh
        MeshData()
    }
    
    private func createTestPointCloud(density: Float) -> PointCloudData {
        // Implementation to create test point cloud
        PointCloudData()
    }
    
    private func createTestMetadata(
        pattern: GrowthPattern,
        texture: TextureMetrics
    ) -> ScanMetadata {
        // Implementation to create test metadata
        ScanMetadata()
    }
}