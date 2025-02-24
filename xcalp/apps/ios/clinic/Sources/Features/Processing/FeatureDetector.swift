import Foundation
import ModelIO
import simd

class FeatureDetector {
    private let curvatureThreshold: Float = 0.85
    private let neighborhoodSize: Int = 8
    
    func detectFeatures(in mesh: MDLMesh) -> [FeaturePoint] {
        guard let vertexBuffer = mesh.vertexBuffers.first?.buffer,
              let vertexData = vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self) else {
            return []
        }
        
        let vertices = Array(UnsafeBufferPointer(start: vertexData, count: mesh.vertexCount))
        var features: [FeaturePoint] = []
        
        for i in 0..<mesh.vertexCount {
            let vertex = vertices[i]
            let neighbors = findNeighbors(for: i, in: mesh, maxCount: neighborhoodSize)
            let neighborPositions = neighbors.map { vertices[$0] }
            
            // Calculate local geometric properties
            let normal = calculateNormal(at: vertex, with: neighborPositions)
            let curvature = calculateCurvature(at: vertex, with: neighborPositions, normal: normal)
            let sharpness = calculateSharpness(at: vertex, with: neighborPositions, normal: normal)
            
            // Feature classification
            if let featureType = classifyFeature(curvature: curvature, sharpness: sharpness) {
                features.append(FeaturePoint(
                    index: i,
                    position: vertex,
                    normal: normal,
                    featureType: featureType,
                    importance: calculateFeatureImportance(curvature: curvature, sharpness: sharpness)
                ))
            }
        }
        
        return features
    }
    
    private func findNeighbors(for vertexIndex: Int, in mesh: MDLMesh, maxCount: Int) -> [Int] {
        guard let submesh = mesh.submeshes.first as? MDLSubmesh,
              let indexBuffer = submesh.indexBuffer,
              let indexData = indexBuffer.contents().assumingMemoryBound(to: UInt32.self) else {
            return []
        }
        
        let indices = Array(UnsafeBufferPointer(start: indexData, count: submesh.indexCount))
        var neighbors = Set<Int>()
        
        // Find connected vertices through triangles
        for i in stride(from: 0, to: indices.count, by: 3) {
            let triangle = (Int(indices[i]), Int(indices[i + 1]), Int(indices[i + 2]))
            
            if triangle.0 == vertexIndex {
                neighbors.insert(triangle.1)
                neighbors.insert(triangle.2)
            } else if triangle.1 == vertexIndex {
                neighbors.insert(triangle.0)
                neighbors.insert(triangle.2)
            } else if triangle.2 == vertexIndex {
                neighbors.insert(triangle.0)
                neighbors.insert(triangle.1)
            }
            
            if neighbors.count >= maxCount {
                break
            }
        }
        
        return Array(neighbors)
    }
    
    private func calculateNormal(at vertex: SIMD3<Float>, with neighbors: [SIMD3<Float>]) -> SIMD3<Float> {
        var normal = SIMD3<Float>.zero
        
        // Calculate weighted average of face normals
        for i in 0..<neighbors.count {
            let j = (i + 1) % neighbors.count
            let v1 = neighbors[i] - vertex
            let v2 = neighbors[j] - vertex
            normal += cross(v1, v2)
        }
        
        return normalize(normal)
    }
    
    private func calculateCurvature(at vertex: SIMD3<Float>, with neighbors: [SIMD3<Float>], normal: SIMD3<Float>) -> Float {
        var curvature: Float = 0
        let vertexNeighbors = neighbors.map { $0 - vertex }
        
        for neighbor in vertexNeighbors {
            let projection = dot(neighbor, normal)
            curvature += abs(projection)
        }
        
        return curvature / Float(neighbors.count)
    }
    
    private func calculateSharpness(at vertex: SIMD3<Float>, with neighbors: [SIMD3<Float>], normal: SIMD3<Float>) -> Float {
        var maxAngle: Float = 0
        
        for i in 0..<neighbors.count {
            let j = (i + 1) % neighbors.count
            let v1 = normalize(neighbors[i] - vertex)
            let v2 = normalize(neighbors[j] - vertex)
            let angle = acos(dot(v1, v2))
            maxAngle = max(maxAngle, angle)
        }
        
        return maxAngle
    }
    
    private func classifyFeature(curvature: Float, sharpness: Float) -> FeatureType? {
        if sharpness > .pi * 0.75 {
            return .corner
        } else if curvature > curvatureThreshold {
            return .edge
        } else if curvature > curvatureThreshold * 0.5 {
            return .ridge
        }
        return nil
    }
    
    private func calculateFeatureImportance(curvature: Float, sharpness: Float) -> Float {
        // Combine curvature and sharpness into a single importance score
        return (curvature + sharpness * 0.5) / 1.5
    }
}

enum FeatureType {
    case corner
    case edge
    case ridge
}

struct FeaturePoint {
    let index: Int
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let featureType: FeatureType
    let importance: Float
}