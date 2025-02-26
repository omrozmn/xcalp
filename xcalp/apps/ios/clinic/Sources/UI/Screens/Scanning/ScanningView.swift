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
                    scanningMode: viewStore.scanningMode,
                    onFrameProcessed: { result in
                        viewStore.send(.frameProcessed(result))
                    }
                )
                
                VStack {
                    // Status overlay
                    ScanningStatusOverlay(
                        status: viewStore.scanningStatus,
                        quality: viewStore.currentQuality,
                        progress: viewStore.scanningProgress
                    )
                    
                    Spacer()
                    
                    // Controls
                    ScanningControlsView(
                        isScanning: viewStore.isScanning,
                        mode: viewStore.scanningMode,
                        onStartScanning: {
                            viewStore.send(.startScanningTapped)
                        },
                        onStopScanning: {
                            viewStore.send(.stopScanningTapped)
                        },
                        onModeChanged: { mode in
                            viewStore.send(.scanningModeChanged(mode))
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("3D Scanning")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Scanning Error",
                isPresented: viewStore.binding(
                    get: { $0.error != nil },
                    send: ScanningFeature.Action.dismissError
                ),
                presenting: viewStore.error
            ) { _ in
                Button("OK") { viewStore.send(.dismissError) }
            } message: { error in
                Text(error.localizedDescription)
            }
            .onAppear { viewStore.send(.onAppear) }
        }
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let isScanning: Bool
    let scanningMode: ScanningMode
    let onFrameProcessed: (FrameProcessingResult) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if isScanning {
            startScanning(uiView, context: context)
        } else {
            stopScanning(uiView)
        }
    }
    
    private func startScanning(_ view: ARSCNView, context: Context) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        view.session.run(configuration)
    }
    
    private func stopScanning(_ view: ARSCNView) {
        view.session.pause()
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard parent.isScanning else { return }
            
            Task {
                do {
                    let coordinator = try await ScanningSystemCoordinator(device: MTLCreateSystemDefaultDevice()!)
                    let result = try await coordinator.processFrame(frame)
                    await MainActor.run {
                        parent.onFrameProcessed(result)
                    }
                } catch {
                    print("Error processing frame: \(error)")
                }
            }
        }
    }
}

private struct ScanningStatusOverlay: View {
    let status: ScanningStatus
    let quality: QualityAssessment?
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            Text(status.description)
                .font(.headline)
            
            if let quality = quality {
                QualityIndicator(quality: quality)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

private struct ScanningControlsView: View {
    let isScanning: Bool
    let mode: ScanningMode
    let onStartScanning: () -> Void
    let onStopScanning: () -> Void
    let onModeChanged: (ScanningMode) -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            Picker("Mode", selection: .init(
                get: { mode },
                set: onModeChanged
            )) {
                Text("LiDAR").tag(ScanningMode.lidar)
                Text("Photo").tag(ScanningMode.photogrammetry)
                Text("Hybrid").tag(ScanningMode.hybrid)
            }
            .pickerStyle(.segmented)
            
            Button(isScanning ? "Stop" : "Start") {
                if isScanning {
                    onStopScanning()
                } else {
                    onStartScanning()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

private struct QualityIndicator: View {
    let quality: QualityAssessment
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: qualityIcon)
                .foregroundColor(qualityColor)
            Text(qualityText)
                .font(.caption)
        }
    }
    
    private var qualityIcon: String {
        switch quality.overallQuality {
        case .high: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "xmark.circle.fill"
        }
    }
    
    private var qualityColor: Color {
        switch quality.overallQuality {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
    
    private var qualityText: String {
        switch quality.overallQuality {
        case .high: return "High Quality"
        case .medium: return "Medium Quality"
        case .low: return "Low Quality"
        }
    }
}

// MARK: - Supporting Types
public enum ScanningStatus: CustomStringConvertible {
    case ready
    case initializing
    case scanning
    case processing
    case completed
    case failed(Error)
    
    public var description: String {
        switch self {
        case .ready: return "Ready to scan"
        case .initializing: return "Initializing..."
        case .scanning: return "Scanning in progress..."
        case .processing: return "Processing scan..."
        case .completed: return "Scan completed"
        case .failed(let error): return "Error: \(error.localizedDescription)"
        }
    }
}

public enum ScanningQuality: Equatable {
    case high
    case medium
    case low
}
