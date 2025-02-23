import Foundation
import RealityKit
import ARKit
import UIKit

public final class ScanVisualizationHelper {
    private var overlayNode: ModelEntity?
    private var surfaceNode: ModelEntity?
    private var progressIndicator: ModelEntity?
    
    public func updateOverlay(in arView: ARView, for quality: ScanningFeature.ScanQuality) {
        // Remove existing overlay
        overlayNode?.removeFromParent()
        
        // Create new overlay based on quality
        let material = SimpleMaterial(
            color: quality.color,
            roughness: 0.5,
            isMetallic: false
        )
        
        let mesh = MeshResource.generatePlane(width: 0.1, height: 0.1)
        overlayNode = ModelEntity(mesh: mesh, materials: [material])
        
        if let overlayNode = overlayNode {
            // Position overlay in view
            let anchor = AnchorEntity(.camera)
            anchor.addChild(overlayNode)
            arView.scene.addAnchor(anchor)
            
            // Add fade animation
            overlayNode.opacity = 0.7
            overlayNode.transform.scale = .zero
            
            withAnimation(.easeInOut(duration: 0.3)) {
                overlayNode.transform.scale = .one
            }
        }
    }
    
    public func updateSurfaceVisualization(in arView: ARView, meshAnchors: [ARMeshAnchor]) {
        // Remove existing surface visualization
        surfaceNode?.removeFromParent()
        
        // Create material for surface visualization
        let material = SimpleMaterial(
            color: .blue.withAlphaComponent(0.3),
            roughness: 0.8,
            isMetallic: false
        )
        
        // Combine all mesh anchors into one visualization
        var vertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        var currentIndex: UInt32 = 0
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            
            // Transform vertices to world space
            for i in 0..<geometry.vertices.count {
                let vertex = geometry.vertices[i]
                let worldVertex = transform.transformPoint(vertex)
                vertices.append(worldVertex)
            }
            
            // Add face indices
            for i in 0..<geometry.faces.count {
                let face = geometry.faces[i]
                triangleIndices.append(face + currentIndex)
            }
            
            currentIndex += UInt32(geometry.vertices.count)
        }
        
        // Create mesh descriptor
        let meshDescriptor = MeshDescriptor(
            name: "ScanSurface",
            vertices: vertices,
            triangleIndices: triangleIndices
        )
        
        // Create mesh resource
        if let meshResource = try? MeshResource.generate(from: [meshDescriptor]) {
            surfaceNode = ModelEntity(mesh: meshResource, materials: [material])
            
            if let surfaceNode = surfaceNode {
                let anchor = AnchorEntity(.world(transform: .identity))
                anchor.addChild(surfaceNode)
                arView.scene.addAnchor(anchor)
            }
        }
    }
    
    public func updateProgressIndicator(in arView: ARView, progress: Float) {
        // Remove existing progress indicator
        progressIndicator?.removeFromParent()
        
        // Create progress ring
        let radius: Float = 0.05
        let thickness: Float = 0.005
        let segments = 32
        
        var vertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        
        // Generate ring vertices
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi * progress
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            
            // Outer vertex
            vertices.append([x + thickness, y, 0])
            // Inner vertex
            vertices.append([x - thickness, y, 0])
            
            if i > 0 {
                let baseIndex = UInt32((i - 1) * 2)
                triangleIndices.append(baseIndex)
                triangleIndices.append(baseIndex + 1)
                triangleIndices.append(baseIndex + 2)
                triangleIndices.append(baseIndex + 1)
                triangleIndices.append(baseIndex + 3)
                triangleIndices.append(baseIndex + 2)
            }
        }
        
        // Create mesh descriptor
        let meshDescriptor = MeshDescriptor(
            name: "ProgressRing",
            vertices: vertices,
            triangleIndices: triangleIndices
        )
        
        // Create mesh resource
        if let meshResource = try? MeshResource.generate(from: [meshDescriptor]) {
            let material = SimpleMaterial(
                color: .green,
                roughness: 0.5,
                isMetallic: true
            )
            
            progressIndicator = ModelEntity(mesh: meshResource, materials: [material])
            
            if let progressIndicator = progressIndicator {
                let anchor = AnchorEntity(.camera)
                anchor.addChild(progressIndicator)
                arView.scene.addAnchor(anchor)
                
                // Position in bottom-right corner
                progressIndicator.position = [0.15, -0.15, -0.3]
                progressIndicator.orientation = simd_quatf(angle: .pi/2, axis: [1, 0, 0])
            }
        }
    }
}

extension ScanningFeature.ScanQuality {
    var color: UIColor {
        switch self {
        case .good:
            return .green
        case .fair:
            return .yellow
        case .poor:
            return .red
        case .unknown:
            return .gray
        }
    }
}
