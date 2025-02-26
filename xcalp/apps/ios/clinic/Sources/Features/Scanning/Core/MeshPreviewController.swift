import RealityKit
import Combine
import SwiftUI

public class MeshPreviewController {
    private var previewEntity: ModelEntity?
    private let updateQueue = DispatchQueue(label: "com.xcalp.meshPreview")
    private let meshProcessor: MeshProcessor
    private var updateTimer: Timer?
    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 0.1 // 10 FPS preview update
    
    public var onMeshUpdated: ((ModelEntity) -> Void)?
    
    init(meshProcessor: MeshProcessor) {
        self.meshProcessor = meshProcessor
    }
    
    public func startPreview() {
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updatePreviewIfNeeded()
        }
    }
    
    public func stopPreview() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    public func updatePreview(with points: [Point3D]) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastUpdateTime >= updateInterval else { return }
        
        updateQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let mesh = try self.meshProcessor.generateMesh(from: points)
                let entity = try ModelEntity(mesh: mesh)
                
                // Apply preview-specific material
                entity.model?.materials = [self.createPreviewMaterial()]
                
                DispatchQueue.main.async {
                    self.previewEntity = entity
                    self.onMeshUpdated?(entity)
                }
                
                self.lastUpdateTime = currentTime
            } catch {
                print("Failed to update preview: \(error)")
            }
        }
    }
    
    private func createPreviewMaterial() -> Material {
        var material = SimpleMaterial()
        material.baseColor = MaterialColorParameter.color(.blue.opacity(0.5))
        material.roughness = MaterialScalarParameter(floatLiteral: 0.5)
        material.metallic = MaterialScalarParameter(floatLiteral: 0.0)
        return material
    }
    
    private func updatePreviewIfNeeded() {
        // This method would be called by the timer to trigger preview updates
        // Implementation would depend on how we're getting point cloud updates
    }
}