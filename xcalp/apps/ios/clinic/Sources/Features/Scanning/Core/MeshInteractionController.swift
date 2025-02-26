import UIKit
import RealityKit
import Combine

public class MeshInteractionController {
    private weak var arView: ARView?
    private var lastPanLocation: CGPoint?
    private var lastPinchScale: CGFloat = 1.0
    private var previewEntity: ModelEntity?
    
    private var rotationGesture: UIPanGestureRecognizer?
    private var pinchGesture: UIPinchGestureRecognizer?
    
    public init(arView: ARView) {
        self.arView = arView
        setupGestures()
    }
    
    public func updatePreviewEntity(_ entity: ModelEntity) {
        self.previewEntity = entity
    }
    
    private func setupGestures() {
        guard let arView = arView else { return }
        
        // Rotation gesture
        let rotation = UIPanGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotation)
        self.rotationGesture = rotation
        
        // Scale gesture
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
        self.pinchGesture = pinch
    }
    
    @objc private func handleRotation(_ gesture: UIPanGestureRecognizer) {
        guard let entity = previewEntity else { return }
        
        switch gesture.state {
        case .began:
            lastPanLocation = gesture.location(in: arView)
            
        case .changed:
            guard let lastLocation = lastPanLocation,
                  let currentLocation = gesture.location(in: arView).converting(to: CGPoint.self) else {
                return
            }
            
            let delta = currentLocation - lastLocation
            
            // Convert pan gesture to rotation
            let sensitivity: Float = 0.01
            let rotationY = simd_quatf(angle: Float(delta.x) * sensitivity,
                                     axis: [0, 1, 0])
            let rotationX = simd_quatf(angle: Float(delta.y) * sensitivity,
                                     axis: [1, 0, 0])
            
            entity.orientation = rotationY * rotationX * entity.orientation
            
            lastPanLocation = currentLocation
            
        case .ended, .cancelled:
            lastPanLocation = nil
            
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let entity = previewEntity else { return }
        
        switch gesture.state {
        case .began:
            lastPinchScale = 1.0
            
        case .changed:
            let delta = gesture.scale / lastPinchScale
            let newScale = entity.scale * Float(delta)
            
            // Limit scaling range
            let minScale: Float = 0.5
            let maxScale: Float = 2.0
            entity.scale = simd_clamp(newScale, min: minScale, max: maxScale)
            
            lastPinchScale = gesture.scale
            
        default:
            break
        }
    }
}

// Helper extensions
private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    func converting(to type: CGPoint.Type) -> CGPoint? {
        return self
    }
}