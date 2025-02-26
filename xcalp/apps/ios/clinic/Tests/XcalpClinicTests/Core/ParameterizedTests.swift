import XCTest
import Metal
@testable import xcalp

final class ParameterizedTests: MeshProcessingTestFixture {
    // Test parameters
    struct ProcessingParameters {
        let resolution: Int
        let smoothingIterations: Int
        let featureThreshold: Float
        let qualityThreshold: Float
        let optimizationLevel: OptimizationLevel
        
        enum OptimizationLevel: Int {
            case minimal = 1
            case balanced = 2
            case aggressive = 3
        }
    }
    
    // Test combinations
    lazy var testParameters: [ProcessingParameters] = {
        var params: [ProcessingParameters] = []
        
        // Test different resolution levels
        for resolution in [32, 64, 128] {
            // Test different smoothing iterations
            for iterations in [1, 3, 5] {
                // Test different feature thresholds
                for threshold in [0.1, 0.3, 0.5] {
                    // Test different optimization levels
                    for level in ProcessingParameters.OptimizationLevel.allCases {
                        params.append(ProcessingParameters(
                            resolution: resolution,
                            smoothingIterations: iterations,
                            featureThreshold: threshold,
                            qualityThreshold: 0.8,
                            optimizationLevel: level
                        ))
                    }
                }
            }
        }
        
        return params
    }()
    
    func testParameterizedProcessing() async throws {
        for params in testParameters {
            // Generate test mesh based on parameters
            let testMesh = TestMeshGenerator.generateTestMesh(
                .sphere,
                resolution: params.resolution
            )
            
            // Configure processing pipeline
            let pipeline = try configurePipeline(with: params)
            
            // Process mesh
            let processedMesh = try await pipeline.process(testMesh)
            
            // Validate results based on parameters
            try validateProcessedMesh(
                processedMesh,
                originalMesh: testMesh,
                parameters: params
            )
        }
    }
    
    func testFeaturePreservation() async throws {
        let featureThresholds: [Float] = [0.1, 0.3, 0.5, 0.7, 0.9]
        
        for threshold in featureThresholds {
            let params = ProcessingParameters(
                resolution: 64,
                smoothingIterations: 3,
                featureThreshold: threshold,
                qualityThreshold: 0.8,
                optimizationLevel: .balanced
            )
            
            // Generate test mesh with features
            let testMesh = createFeatureMesh(featureStrength: threshold)
            
            // Process mesh
            let pipeline = try configurePipeline(with: params)
            let processedMesh = try await pipeline.process(testMesh)
            
            // Validate feature preservation
            try validateFeaturePreservation(
                original: testMesh,
                processed: processedMesh,
                threshold: threshold
            )
        }
    }
    
    func testQualityThresholds() async throws {
        let qualityLevels: [Float] = [0.6, 0.7, 0.8, 0.9]
        
        for quality in qualityLevels {
            let params = ProcessingParameters(
                resolution: 64,
                smoothingIterations: 3,
                featureThreshold: 0.3,
                qualityThreshold: quality,
                optimizationLevel: .balanced
            )
            
            // Generate test mesh
            let testMesh = TestMeshGenerator.generateTestMesh(.sphere)
            
            // Process mesh
            let pipeline = try configurePipeline(with: params)
            let processedMesh = try await pipeline.process(testMesh)
            
            // Validate quality metrics
            try validateQualityMetrics(
                processedMesh,
                expectedQuality: quality
            )
        }
    }
    
    func testOptimizationLevels() async throws {
        for level in ProcessingParameters.OptimizationLevel.allCases {
            let params = ProcessingParameters(
                resolution: 64,
                smoothingIterations: 3,
                featureThreshold: 0.3,
                qualityThreshold: 0.8,
                optimizationLevel: level
            )
            
            // Generate complex test mesh
            let testMesh = createComplexMesh()
            
            // Process mesh
            let pipeline = try configurePipeline(with: params)
            let processedMesh = try await pipeline.process(testMesh)
            
            // Validate optimization results
            try validateOptimizationLevel(
                original: testMesh,
                processed: processedMesh,
                level: level
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func configurePipeline(
        with params: ProcessingParameters
    ) throws -> MeshProcessingPipeline {
        return try MeshProcessingPipeline(
            device: device,
            configuration: .init(
                smoothingIterations: params.smoothingIterations,
                featureThreshold: params.featureThreshold,
                qualityThreshold: params.qualityThreshold,
                optimizationLevel: params.optimizationLevel.rawValue
            )
        )
    }
    
    private func validateProcessedMesh(
        _ processed: MeshData,
        originalMesh: MeshData,
        parameters: ProcessingParameters
    ) throws {
        // Validate mesh integrity
        try validateMeshTopology(processed)
        
        // Validate vertex count based on optimization level
        let expectedReduction: Float
        switch parameters.optimizationLevel {
        case .minimal:
            expectedReduction = 0.9
        case .balanced:
            expectedReduction = 0.7
        case .aggressive:
            expectedReduction = 0.5
        }
        
        XCTAssertLessThanOrEqual(
            Float(processed.vertices.count) / Float(originalMesh.vertices.count),
            expectedReduction,
            "Insufficient mesh reduction for optimization level"
        )
        
        // Validate quality metrics
        let quality = try qualityAnalyzer.analyzeMesh(processed)
        XCTAssertGreaterThanOrEqual(
            quality.surfaceCompleteness,
            parameters.qualityThreshold,
            "Quality below threshold"
        )
    }
    
    private func validateFeaturePreservation(
        original: MeshData,
        processed: MeshData,
        threshold: Float
    ) throws {
        let originalFeatures = detectFeatures(original, threshold: threshold)
        let processedFeatures = detectFeatures(processed, threshold: threshold)
        
        let preservationRate = Float(processedFeatures.count) / Float(originalFeatures.count)
        XCTAssertGreaterThanOrEqual(
            preservationRate,
            1.0 - threshold,
            "Feature preservation below expected threshold"
        )
    }
    
    private func validateQualityMetrics(
        _ mesh: MeshData,
        expectedQuality: Float
    ) throws {
        let quality = try qualityAnalyzer.analyzeMesh(mesh)
        
        XCTAssertGreaterThanOrEqual(
            quality.surfaceCompleteness,
            expectedQuality,
            "Surface completeness below threshold"
        )
        
        XCTAssertGreaterThanOrEqual(
            quality.featurePreservation,
            expectedQuality,
            "Feature preservation below threshold"
        )
        
        XCTAssertLessThanOrEqual(
            quality.noiseLevel,
            1.0 - expectedQuality,
            "Noise level above threshold"
        )
    }
    
    private func validateOptimizationLevel(
        original: MeshData,
        processed: MeshData,
        level: ProcessingParameters.OptimizationLevel
    ) throws {
        let vertexRatio = Float(processed.vertices.count) / Float(original.vertices.count)
        
        switch level {
        case .minimal:
            XCTAssertGreaterThanOrEqual(vertexRatio, 0.8)
        case .balanced:
            XCTAssertGreaterThanOrEqual(vertexRatio, 0.5)
            XCTAssertLessThanOrEqual(vertexRatio, 0.8)
        case .aggressive:
            XCTAssertLessThanOrEqual(vertexRatio, 0.5)
        }
        
        // Validate mesh quality hasn't degraded too much
        let quality = try qualityAnalyzer.analyzeMesh(processed)
        XCTAssertGreaterThanOrEqual(
            quality.surfaceCompleteness,
            0.7,
            "Quality degraded too much after optimization"
        )
    }
    
    private func detectFeatures(_ mesh: MeshData, threshold: Float) -> [(Int, Int)] {
        var features: [(Int, Int)] = []
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.normals[Int(mesh.indices[i])]
            let v2 = mesh.normals[Int(mesh.indices[i + 1])]
            
            let angle = acos(dot(v1, v2))
            if angle > threshold * .pi {
                features.append((Int(mesh.indices[i]), Int(mesh.indices[i + 1])))
            }
        }
        
        return features
    }
    
    private func createFeatureMesh(featureStrength: Float) -> MeshData {
        // Create a mesh with controlled feature sharpness
        let mesh = TestMeshGenerator.generateTestMesh(.cube)
        
        var modifiedNormals = mesh.normals
        for i in 0..<modifiedNormals.count {
            let noise = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            modifiedNormals[i] = normalize(
                modifiedNormals[i] + noise * (1.0 - featureStrength)
            )
        }
        
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: modifiedNormals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
    
    private func createComplexMesh() -> MeshData {
        // Create a mesh with varied geometric features
        let resolution = 64
        let mesh = TestMeshGenerator.generateTestMesh(.sphere, resolution: resolution)
        
        var modifiedVertices = mesh.vertices
        for i in 0..<modifiedVertices.count {
            let noise = SIMD3<Float>(
                Float.random(in: -0.1...0.1),
                Float.random(in: -0.1...0.1),
                Float.random(in: -0.1...0.1)
            )
            modifiedVertices[i] += noise
        }
        
        return MeshData(
            vertices: modifiedVertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}