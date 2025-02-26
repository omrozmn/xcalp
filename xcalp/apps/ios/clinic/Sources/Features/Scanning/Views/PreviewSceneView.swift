import SwiftUI
import RealityKit

public struct PreviewSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: ScanningFeature
    private let previewView = ARView(frame: .zero)
    private var interactionController: MeshInteractionController?
    private let accessibilityManager = AccessibilityManager()
    
    public func makeUIView(context: Context) -> ARView {
        let view = previewView
        view.environment.background = .color(.black.withAlphaComponent(0.1))
        
        // Configure preview scene
        let scene = setupPreviewScene()
        view.scene = scene
        
        // Configure debug options for better visualization
        view.debugOptions = [.showSceneUnderstanding]
        
        // Setup interaction controller
        interactionController = MeshInteractionController(arView: view)
        
        // Setup accessibility
        setupAccessibility(for: view)
        
        return view
    }
    
    private func setupAccessibility(for view: ARView) {
        accessibilityManager.setupAccessibility(
            for: view,
            qualityHandler: { quality in
                accessibilityManager.announceQuality(quality)
            },
            guidanceHandler: { guidance in 
                accessibilityManager.announceGuidance(guidance)
            }
        )
        
        // Add accessibility gestures
        let doubleTapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        
        // Update accessibility frame
        view.accessibilityFrame = view.bounds
        view.accessibilityTraits = [.allowsDirectInteraction, .updatesFrequently]
    }
    
    public func updateUIView(_ uiView: ARView, context: Context) {
        if let entity = viewModel.currentPreviewEntity {
            interactionController?.updatePreviewEntity(entity)
            
            // Update accessibility
            if UIAccessibility.isVoiceOverRunning {
                accessibilityManager.announceProgress(viewModel.scanningProgress)
            }
        }
    }
    
    private func setupPreviewScene() -> Scene {
        let scene = Scene()
        
        // Add ambient light
        let ambientLight = AmbientLight()
        ambientLight.intensity = 1000
        let lightAnchor = AnchorEntity()
        lightAnchor.addChild(ambientLight)
        scene.addAnchor(lightAnchor)
        
        // Configure camera
        let cameraAnchor = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.look(at: [0, 0, 0], from: [0, 0, 2], relativeTo: nil)
        cameraAnchor.addChild(camera)
        scene.addAnchor(cameraAnchor)
        
        return scene
    }
    
    public static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
        uiView.scene.anchors.removeAll()
    }
}

// Coordinator to handle AR session updates
extension PreviewSceneView {
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, ARSessionDelegate {
        var parent: PreviewSceneView
        
        init(_ parent: PreviewSceneView) {
            self.parent = parent
        }
        
        @objc func handleDoubleTap() {
            // Provide audio feedback for current scan status
            parent.accessibilityManager.announceQuality(parent.viewModel.scanningQuality)
        }
        
        public func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Handle frame updates for accessibility
            if UIAccessibility.isVoiceOverRunning {
                // Only announce significant changes
                if frame.timestamp.truncatingRemainder(dividingBy: 2.0) < 0.1 {
                    parent.accessibilityManager.announceGuidance(parent.viewModel.guidanceMessage)
                }
            }
        }
    }
}