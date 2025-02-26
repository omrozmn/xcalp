import Foundation
import simd

extension MeshData {
    /// Transform mesh using 4x4 transformation matrix
    func transformed(by transform: simd_float4x4) -> MeshData {
        let transformedVertices = vertices.map { vertex in
            let v4 = simd_float4(vertex.x, vertex.y, vertex.z, 1)
            let transformed = transform * v4
            return SIMD3<Float>(transformed.x / transformed.w,
                              transformed.y / transformed.w,
                              transformed.z / transformed.w)
        }
        
        // Transform normals using inverse transpose matrix
        let normalTransform = transform.inverse.transpose
        let transformedNormals = normals.map { normal in
            let n4 = simd_float4(normal.x, normal.y, normal.z, 0)
            let transformed = normalTransform * n4
            return normalize(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
        }
        
        var transformed = MeshData(
            vertices: transformedVertices,
            indices: indices,
            normals: transformedNormals,
            confidence: confidence,
            metadata: metadata
        )
        
        // Update processing history
        transformed.metadata.processingSteps.append(
            ProcessingStep(
                operation: "transform",
                timestamp: Date(),
                parameters: ["matrix": "\(transform)"],
                qualityImpact: nil
            )
        )
        
        transformed.updateBoundingBox()
        return transformed
    }
    
    /// Calculate quality metrics for the mesh
    func calculateQualityMetrics() -> QualityMetrics {
        // Point density calculation
        let volume = self.volume
        let pointDensity = Float(vertices.count) / volume
        
        // Surface completeness estimation
        let surfaceArea = self.surfaceArea
        let theoreticalArea = pow(volume, 2.0/3.0) * pow(36.0 * .pi, 1.0/3.0)
        let surfaceCompleteness = min(surfaceArea / theoreticalArea, 1.0)
        
        // Noise level estimation using average deviation from local planes
        let noiseLevel = calculateNoiseLevel()
        
        // Feature preservation using curvature analysis
        let featurePreservation = calculateFeaturePreservation()
        
        return QualityMetrics(
            pointDensity: pointDensity,
            surfaceCompleteness: surfaceCompleteness,
            noiseLevel: noiseLevel,
            featurePreservation: featurePreservation
        )
    }
    
    private func calculateNoiseLevel() -> Float {
        var totalDeviation: Float = 0
        var sampleCount = 0
        
        for (idx, vertex) in vertices.enumerated() {
            let neighbors = findNeighborVertices(for: idx)
            guard neighbors.count >= 3 else { continue }
            
            // Fit plane to neighbors
            let centroid = neighbors.reduce(SIMD3<Float>.zero, +) / Float(neighbors.count)
            let normal = normals[idx]
            
            // Calculate average deviation from plane
            let deviations = neighbors.map { neighbor in
                abs(dot(neighbor - centroid, normal))
            }
            
            totalDeviation += deviations.reduce(0, +) / Float(deviations.count)
            sampleCount += 1
        }
        
        return sampleCount > 0 ? totalDeviation / Float(sampleCount) : 0
    }
    
    private func calculateFeaturePreservation() -> Float {
        let curvatures = calculateCurvature()
        let maxCurvature = curvatures.max() ?? 0
        
        guard maxCurvature > 0 else { return 1.0 }
        
        // Calculate how well high-curvature regions are preserved
        var featureScore: Float = 0
        var featureCount = 0
        
        for (idx, curvature) in curvatures.enumerated() {
            if curvature > maxCurvature * 0.2 { // Consider top 20% as features
                let confidence = self.confidence[idx]
                featureScore += confidence
                featureCount += 1
            }
        }
        
        return featureCount > 0 ? featureScore / Float(featureCount) : 1.0
    }
    
    private func findNeighborVertices(for index: Int) -> [SIMD3<Float>] {
        var neighbors: [SIMD3<Float>] = []
        let vertex = vertices[index]
        
        // Search connected vertices through triangle indices
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            if i1 == index {
                neighbors.append(vertices[i2])
                neighbors.append(vertices[i3])
            } else if i2 == index {
                neighbors.append(vertices[i1])
                neighbors.append(vertices[i3])
            } else if i3 == index {
                neighbors.append(vertices[i1])
                neighbors.append(vertices[i2])
            }
        }
        
        return neighbors
    }
}