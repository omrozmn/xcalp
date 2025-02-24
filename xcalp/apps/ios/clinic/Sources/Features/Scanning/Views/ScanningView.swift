import SwiftUI
import ARKit
import Combine

struct ScanningView: View {
    @StateObject private var viewModel: ScanningViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(meshProcessor: MeshProcessor) {
        _viewModel = StateObject(wrappedValue: ScanningViewModel(meshProcessor: meshProcessor))
    }
    
    var body: some View {
        ZStack {
            ARViewContainer(session: viewModel.session)
                .edgesIgnoringSafeArea(.all)
                .overlay(QualityOverlay(quality: viewModel.currentQuality))
            
            VStack {
                Spacer()
                controlPanel
            }
            .padding()
        }
        .alert("Scanning Error", isPresented: $viewModel.showError) {
            Button("OK") { dismiss() }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error occurred")
        }
        .onChange(of: viewModel.shouldDismiss) { newValue in
            if newValue {
                dismiss()
            }
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 20) {
            scanningModeIndicator
            
            HStack(spacing: 30) {
                Button(action: viewModel.toggleScanning) {
                    Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 64))
                        .foregroundColor(viewModel.isScanning ? .red : .blue)
                }
                
                if viewModel.isScanning {
                    Button(action: viewModel.finishScanning) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var scanningModeIndicator: some View {
        HStack {
            Image(systemName: viewModel.currentMode.iconName)
            Text(viewModel.currentMode.description)
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(viewModel.currentMode.color.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(viewModel.currentMode.color, lineWidth: 1)
                )
        )
    }
}

private extension ScanningMode {
    var iconName: String {
        switch self {
        case .lidar:
            return "lidar.sensor"
        case .photogrammetry:
            return "camera.fill"
        case .hybrid:
            return "camera.aperture"
        }
    }
    
    var description: String {
        switch self {
        case .lidar:
            return "LiDAR Scanning"
        case .photogrammetry:
            return "Photo Scanning"
        case .hybrid:
            return "Hybrid Mode"
        }
    }
    
    var color: Color {
        switch self {
        case .lidar:
            return .blue
        case .photogrammetry:
            return .orange
        case .hybrid:
            return .purple
        }
    }
}