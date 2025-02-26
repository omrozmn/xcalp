import SwiftUI
import RealityKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ScanningFeature
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        if viewModel.scanningState == .scanning {
            // Update AR view configuration based on scanning mode
            switch viewModel.selectedCamera {
            case .front:
                configureFrontCamera(uiView)
            case .back:
                configureBackCamera(uiView)
            case .none:
                break
            }
        }
    }
    
    private func configureFrontCamera(_ view: ARView) {
        // Configure for TrueDepth
        let config = ARFaceTrackingConfiguration()
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func configureBackCamera(_ view: ARView) {
        // Configure for LiDAR
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            // Handle session failures
            print("AR session failed: \(error)")
        }
    }
}