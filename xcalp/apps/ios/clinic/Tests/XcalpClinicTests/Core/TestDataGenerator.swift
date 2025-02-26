import Foundation
import simd

final class TestDataGenerator {
    enum ScanningCondition {
        case optimal
        case poorLighting
        case motion
        case lowDensity
        case highNoise
        case partialOcclusion
    }
    
    struct SimulatedScanParameters {
        var lightingLevel: Float
        var motionAmount: Float
        var scanningDistance: Float
        var surfaceReflectivity: Float
        var environmentNoise: Float
        var occlusionPercentage: Float
        
        static let optimal = SimulatedScanParameters(
            lightingLevel: 1.0,
            motionAmount: 0.0,
            scanningDistance: 0.3,
            surfaceReflectivity: 0.5,
            environmentNoise: 0.0,
            occlusionPercentage: 0.0
        )
    }
    
    func generateTestData(
        for condition: ScanningCondition,
        meshType: TestMeshGenerator.MeshType
    ) -> (MeshData, SimulatedScanParameters) {
        let baseMesh = TestMeshGenerator.generateTestMesh(meshType)
        let params = generateScanParameters(for: condition)
        
        return (
            applySimulatedConditions(to: baseMesh, with: params),
            params
        )
    }
    
    func generateTestDataset() -> [(MeshData, SimulatedScanParameters)] {
        var dataset: [(MeshData, SimulatedScanParameters)] = []
        
        // Generate data for each condition and mesh type
        for condition in [ScanningCondition.optimal, .poorLighting, .motion, .lowDensity, .highNoise, .partialOcclusion] {
            for meshType in TestConfiguration.testMeshTypes {
                dataset.append(generateTestData(for: condition, meshType: meshType))
            }
        }
        
        return dataset
    }
    
    private func generateScanParameters(for condition: ScanningCondition) -> SimulatedScanParameters {
        var params = SimulatedScanParameters.optimal
        
        switch condition {
        case .optimal:
            return params
            
        case .poorLighting:
            params.lightingLevel = 0.2
            params.environmentNoise = 0.3
            
        case .motion:
            params.motionAmount = 0.4
            params.environmentNoise = 0.2
            
        case .lowDensity:
            params.scanningDistance = 0.8
            params.lightingLevel = 0.7
            
        case .highNoise:
            params.environmentNoise = 0.5
            params.surfaceReflectivity = 0.9
            
        case .partialOcclusion:
            params.occlusionPercentage = 0.3
            params.scanningDistance = 0.4
        }
        
        return params
    }
    
    private func applySimulatedConditions(
        to mesh: MeshData,
        with params: SimulatedScanParameters
    ) -> MeshData {
        var vertices = mesh.vertices
        var normals = mesh.normals
        var confidence = mesh.confidence
        
        // Apply scanning distance effect
        let distanceScale = 1.0 + params.scanningDistance
        vertices = vertices.map { $0 * distanceScale }
        
        // Apply motion blur
        if params.motionAmount > 0 {
            vertices = applyMotionEffect(to: vertices, amount: params.motionAmount)
        }
        
        // Apply noise based on lighting and environment
        let noiseLevel = (1.0 - params.lightingLevel) * 0.5 + params.environmentNoise
        if noiseLevel > 0 {
            vertices = applyNoise(to: vertices, level: noiseLevel)
            normals = recalculateNormals(vertices: vertices, indices: mesh.indices)
        }
        
        // Apply surface reflectivity effects
        confidence = confidence.map { $0 * (1.0 - params.surfaceReflectivity * 0.5) }
        
        // Apply occlusion
        if params.occlusionPercentage > 0 {
            (vertices, normals, confidence) = applyOcclusion(
                vertices: vertices,
                normals: normals,
                confidence: confidence,
                percentage: params.occlusionPercentage
            )
        }
        
        return MeshData(
            vertices: vertices,
            indices: mesh.indices,
            normals: normals,
            confidence: confidence,
            metadata: mesh.metadata
        )
    }
    
    private func applyMotionEffect(
        to vertices: [SIMD3<Float>],
        amount: Float
    ) -> [SIMD3<Float>] {
        let motionVector = SIMD3<Float>(amount, amount * 0.5, amount * 0.2)
        return vertices.map { vertex in
            let offset = motionVector * Float.random(in: -1...1)
            return vertex + offset
        }
    }
    
    private func applyNoise(
        to vertices: [SIMD3<Float>],
        level: Float
    ) -> [SIMD3<Float>] {
        return vertices.map { vertex in
            let noise = SIMD3<Float>(
                Float.random(in: -level...level),
                Float.random(in: -level...level),
                Float.random(in: -level...level)
            )
            return vertex + noise
        }
    }
    
    private func applyOcclusion(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        confidence: [Float],
        percentage: Float
    ) -> ([SIMD3<Float>], [SIMD3<Float>], [Float]) {
        let occlusionCount = Int(Float(vertices.count) * percentage)
        let occludedIndices = Set(Array(0..<vertices.count).shuffled().prefix(occlusionCount))
        
        return (
            vertices.enumerated().map { index, vertex in
                occludedIndices.contains(index) ? vertex + SIMD3<Float>(repeating: .infinity) : vertex
            },
            normals.enumerated().map { index, normal in
                occludedIndices.contains(index) ? .zero : normal
            },
            confidence.enumerated().map { index, conf in
                occludedIndices.contains(index) ? 0.0 : conf
            }
        )
    }
    
    private func recalculateNormals(
        vertices: [SIMD3<Float>],
        indices: [UInt32]
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        
        // Calculate normals for each triangle
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            let v1 = vertices[i1]
            let v2 = vertices[i2]
            let v3 = vertices[i3]
            
            let normal = normalize(cross(v2 - v1, v3 - v1))
            
            normals[i1] += normal
            normals[i2] += normal
            normals[i3] += normal
        }
        
        // Normalize accumulated normals
        return normals.map { normalize($0) }
    }
}