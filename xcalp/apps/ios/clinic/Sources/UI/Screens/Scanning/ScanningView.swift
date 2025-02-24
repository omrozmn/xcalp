import ARKit
import ComposableArchitecture
import RealityKit
import SwiftUI

/// Main view for 3D scanning functionality that handles LiDAR scanning and real-time visualization
/// Uses ARKit and RealityKit for 3D capture with voice guidance and quality monitoring
public struct ScanningView: View {
    let store: StoreOf<ScanningFeature>
    
    public init(store: StoreOf<ScanningFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            ZStack {
                ARViewContainer(
                    isScanning: viewStore.isScanning,
                    scanQuality: viewStore.scanQuality
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("3D scanner view")
                
                VStack {
                    // Top status bar
                    HStack {
                        LidarStatusView(status: viewStore.lidarStatus)
                        Spacer()
                        ScanQualityIndicator(quality: viewStore.scanQuality)
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Scanner status")
                    
                    Spacer()
                    
                    // Guide overlay with accessibility
                    if let guide = viewStore.currentGuide {
                        GuideOverlay(guide: guide)
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityLabel(guide.accessibilityDescription)
                    }
                    
                    // Bottom control panel with accessibility
                    ControlPanel(
                        isScanning: viewStore.isScanning,
                        voiceGuidanceEnabled: viewStore.voiceGuidanceEnabled,
                        onStartScanning: { viewStore.send(.startScanning) },
                        onStopScanning: { viewStore.send(.stopScanning) },
                        onToggleVoiceGuidance: { viewStore.send(.toggleVoiceGuidance) },
                        onCapture: { viewStore.send(.captureButtonTapped) }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Scanning controls")
                }
            }
            .alert(
                item: viewStore.binding(
                    get: \.error,
                    send: { _ in .dismissError }
                )
            ) { error in
                Alert(
                    title: Text("Error"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear { viewStore.send(.onAppear) }
        }
    }
}

// MARK: - Supporting Views
private struct ARViewContainer: UIViewRepresentable {
    let isScanning: Bool
    let scanQuality: ScanningFeature.ScanQuality
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        var meshAnchors: [UUID: ARMeshAnchor] = [:]
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                meshAnchors[meshAnchor.identifier] = meshAnchor
            }
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
                meshAnchors[meshAnchor.identifier] = meshAnchor
            }
        }
        
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            for anchor in anchors {
                meshAnchors.removeValue(forKey: anchor.identifier)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session.delegate = context.coordinator
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // Enable LiDAR-specific features if available
        if type(of: config).supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        // Enable people occlusion for better segmentation
        if type(of: config).supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        view.session.run(config)
        
        // Add tap gesture for focus point
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tapRecognizer)
        
        return view
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        if isScanning {
            // Update visualization based on scan quality
            switch scanQuality {
            case .good:
                uiView.debugOptions = []
            case .fair:
                uiView.debugOptions = [.showSceneUnderstanding]
            case .poor:
                uiView.debugOptions = [.showSceneUnderstanding, .showWorldOrigin]
            case .unknown:
                uiView.debugOptions = [.showWorldOrigin]
            }
        } else {
            uiView.debugOptions = []
        }
    }
}

extension ARViewContainer.Coordinator {
    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view as? ARView else { return }
        let location = recognizer.location(in: view)
        
        // Perform hit testing
        let results = view.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        
        if let firstResult = results.first {
            // Add a focus point visualization
            let focusEntity = ModelEntity(
                mesh: .generateSphere(radius: 0.01),
                materials: [SimpleMaterial(color: .yellow, isMetallic: true)]
            )
            
            let anchor = AnchorEntity(world: firstResult.worldTransform)
            anchor.addChild(focusEntity)
            view.scene.addAnchor(anchor)
            
            // Animate focus point
            focusEntity.scale = .zero
            focusEntity.transform.scale = .zero
            
            withAnimation(.easeInOut(duration: 0.2)) {
                focusEntity.scale = .one
            }
            
            // Remove after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    focusEntity.scale = .zero
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    anchor.removeFromParent()
                }
            }
        }
    }
}

private struct LidarStatusView: View {
    let status: ScanningFeature.LidarStatus
    
    var body: some View {
        Label(
            title: { Text(status.description) },
            icon: { Image(systemName: status.iconName) }
        )
        .foregroundColor(status.color)
    }
}

private struct ScanQualityIndicator: View {
    let quality: ScanningFeature.ScanQuality
    
    var body: some View {
        Label(
            title: { Text(quality.description) },
            icon: { Image(systemName: quality.iconName) }
        )
        .foregroundColor(quality.color)
    }
}

private struct GuideOverlay: View {
    let guide: ScanningFeature.ScanningGuide
    
    var body: some View {
        Text(guide.message)
            .font(XcalpTypography.title3)
            .foregroundColor(.white)
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(XcalpLayout.cornerRadius)
    }
}

private struct ControlPanel: View {
    let isScanning: Bool
    let voiceGuidanceEnabled: Bool
    let onStartScanning: () -> Void
    let onStopScanning: () -> Void
    let onToggleVoiceGuidance: () -> Void
    let onCapture: () -> Void
    
    var body: some View {
        VStack(spacing: XcalpLayout.spacing) {
            // Voice guidance toggle
            Toggle(
                "Voice Guidance",
                isOn: .constant(voiceGuidanceEnabled)
            )
            .onChange(of: voiceGuidanceEnabled) { _ in
                onToggleVoiceGuidance()
            }
            
            HStack(spacing: XcalpLayout.spacing) {
                // Start/Stop button
                Button(
                    action: { isScanning ? onStopScanning() : onStartScanning() }
                ) {
                    Label(
                        isScanning ? "Stop" : "Start",
                        systemImage: isScanning ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                // Capture button
                Button(action: onCapture) {
                    Label("Capture", systemImage: "camera.fill")
                        .font(XcalpTypography.title2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isScanning)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.9))
    }
}

// MARK: - Extensions
extension ScanningFeature.LidarStatus {
    var description: String {
        switch self {
        case .unknown: return "LiDAR Status Unknown"
        case .notAvailable: return "LiDAR Not Available"
        case .calibrating: return "Calibrating LiDAR"
        case .ready: return "LiDAR Ready"
        }
    }
    
    var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .notAvailable: return "xmark.circle"
        case .calibrating: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .notAvailable: return .red
        case .calibrating: return .yellow
        case .ready: return .green
        }
    }
}

extension ScanningFeature.ScanQuality {
    var description: String {
        switch self {
        case .unknown: return "Unknown Quality"
        case .poor: return "Poor Quality"
        case .fair: return "Fair Quality"
        case .good: return "Good Quality"
        case .excellent: return "Excellent Quality"
        }
    }
    
    var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .poor: return "exclamationmark.circle"
        case .fair: return "hand.thumbsup"
        case .good: return "star.fill"
        case .excellent: return "star.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .poor: return .red
        case .fair: return .yellow
        case .good: return .green
        case .excellent: return .blue
        }
    }
}

extension ScanningFeature.ScanningGuide {
    var message: String {
        switch self {
        case .moveCloser: return "Move closer to the subject"
        case .moveFarther: return "Move farther from the subject"
        case .moveSlower: return "Move the device more slowly"
        case .holdSteady: return "Hold the device steady"
        case .scanComplete: return "Scan complete!"
        }
    }
}
