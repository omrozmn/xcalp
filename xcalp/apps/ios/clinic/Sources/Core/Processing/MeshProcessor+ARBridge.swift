import Foundation
import ARKit
import SceneKit

@available(iOS 13.4, *)
extension MeshProcessor {
    // MARK: - ARKit Support
    
    func setupARConfiguration() -> ARConfiguration {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .meshWithClassification
            config.environmentTexturing = .automatic
            config.planeDetection = [.horizontal, .vertical]
            return config
        } else {
            // Fallback to basic configuration
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            return config
        }
    }
    
    func convertARMeshAnchor(_ anchor: ARMeshAnchor) throws -> Mesh {
        let geometry = anchor.geometry
        
        let vertices = Array(UnsafeBufferPointer(
            start: geometry.vertices.buffer.contents()
                .assumingMemoryBound(to: SIMD3<Float>.self),
            count: geometry.vertices.count
        ))
        
        let normals = Array(UnsafeBufferPointer(
            start: geometry.normals.buffer.contents()
                .assumingMemoryBound(to: SIMD3<Float>.self),
            count: geometry.normals.count
        ))
        
        let faces = Array(UnsafeBufferPointer(
            start: geometry.faces.buffer.contents()
                .assumingMemoryBound(to: UInt32.self),
            count: geometry.faces.count * 3
        ))
        
        return Mesh(
            vertices: vertices,
            normals: normals,
            indices: faces
        )
    }
    
    func updateMeshClassification(
        _ mesh: Mesh,
        classifications: ARMeshClassification,
        confidence: ARConfidence
    ) -> MeshClassificationResult {
        var classifiedRegions: [MeshRegion] = []
        var confidenceScores: [Float] = []
        
        for i in 0..<mesh.vertices.count {
            let classification = classifications[i]
            let confidenceValue = confidence[i]
            
            let region = MeshRegion(
                startIndex: i,
                classification: classification.rawValue,
                confidence: Float(confidenceValue.rawValue) / Float(ARConfidence.high.rawValue)
            )
            
            classifiedRegions.append(region)
            confidenceScores.append(region.confidence)
        }
        
        return MeshClassificationResult(
            regions: classifiedRegions,
            averageConfidence: confidenceScores.reduce(0, +) / Float(confidenceScores.count)
        )
    }
    
    func generateReferenceGeometry(from anchor: ARMeshAnchor) -> SCNGeometry {
        let vertices = anchor.geometry.vertices
        let normals = anchor.geometry.normals
        let faces = anchor.geometry.faces
        
        let vertexSource = SCNGeometrySource(
            vertices: Array(UnsafeBufferPointer(
                start: vertices.buffer.contents().assumingMemoryBound(to: SCNVector3.self),
                count: vertices.count
            ))
        )
        
        let normalSource = SCNGeometrySource(
            normals: Array(UnsafeBufferPointer(
                start: normals.buffer.contents().assumingMemoryBound(to: SCNVector3.self),
                count: normals.count
            ))
        )
        
        let element = SCNGeometryElement(
            data: faces.buffer.contents().assumingMemoryBound(to: Int32.self),
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
}

// MARK: - Supporting Types

struct MeshRegion {
    let startIndex: Int
    let classification: UInt
    let confidence: Float
}

struct MeshClassificationResult {
    let regions: [MeshRegion]
    let averageConfidence: Float
    
    var isReliable: Bool {
        averageConfidence >= ClinicalConstants.minimumNormalConsistency
    }
}

extension ARMeshClassification {
    var description: String {
        switch self {
        case .wall: return "Wall"
        case .floor: return "Floor"
        case .ceiling: return "Ceiling"
        case .table: return "Table"
        case .seat: return "Seat"
        case .window: return "Window"
        case .door: return "Door"
        case .none: return "None"
        @unknown default: return "Unknown"
        }
    }
}
