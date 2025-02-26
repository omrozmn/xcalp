import SwiftUI
import ARKit

struct ComprehensiveScanningPreviewView: View {
    @StateObject var viewModel: ScanningPreviewViewModel
    @Environment(\.accessibilityEnabled) var accessibilityEnabled
    
    var body: some View {
        ZStack {
            // AR Preview Scene
            PreviewSceneView()
            
            // Overlay Elements
            VStack {
                // Top controls
                HStack {
                    Button(action: { viewModel.isShowingPreferences = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Scanning Preferences")
                    
                    Spacer()
                    
                    Button(action: viewModel.toggleGuide) {
                        Image(systemName: viewModel.showingGuide ? "eye.slash" : "eye")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(viewModel.showingGuide ? "Hide Scanning Guide" : "Show Scanning Guide")
                }
                .padding()
                
                if viewModel.showingGuide {
                    // Scanning overlay with all feedback elements
                    ScanningOverlayView(
                        scanningQuality: viewModel.scanningQuality,
                        coverage: viewModel.coverage,
                        hints: viewModel.hints,
                        guideMessage: viewModel.guidanceMessage,
                        metrics: viewModel.metrics,
                        showingGuide: viewModel.showingGuide
                    )
                }
                
                Spacer()
                
                // Bottom metrics
                VStack(spacing: 16) {
                    if viewModel.shouldShowSpeedGauge {
                        SpeedGaugeView(
                            currentSpeed: viewModel.currentSpeed,
                            optimalSpeed: viewModel.optimizedSpeed,
                            guidance: viewModel.speedGuidance
                        )
                    }
                    
                    if viewModel.shouldShowMetrics {
                        ScanQualityMetricsView(
                            quality: viewModel.scanningQuality,
                            pointCount: 0,
                            coverage: viewModel.coverage,
                            blurAmount: 0,
                            isCompensatingBlur: false
                        )
                    }
                    
                    // Capture button
                    Button(action: attemptCapture) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Capture")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(captureButtonColor)
                        .clipShape(Capsule())
                    }
                    .disabled(!viewModel.canCapture)
                    .accessibilityLabel(captureButtonAccessibilityLabel)
                }
                .padding()
            }
        }
        .sheet(isPresented: $viewModel.isShowingPreferences) {
            ScanningPreferencesView(preferences: $viewModel.preferences)
        }
        .onChange(of: viewModel.preferences) { _ in
            viewModel.updatePreferences()
        }
    }
    
    private func attemptCapture() {
        // Trigger capture in scanning feature
        // Implementation would be added here
    }
    
    private var captureButtonColor: Color {
        if !viewModel.canCapture {
            return .gray
        }
        return viewModel.isQualityAcceptable && viewModel.isCoverageAcceptable ? .green : .orange
    }
    
    private var captureButtonAccessibilityLabel: String {
        if !viewModel.isQualityAcceptable {
            return "Cannot capture - Quality too low"
        }
        if !viewModel.isCoverageAcceptable {
            return "Cannot capture - Insufficient coverage"
        }
        return "Capture scan"
    }
}

#if DEBUG
struct ComprehensiveScanningPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        ComprehensiveScanningPreviewView(
            viewModel: ScanningPreviewViewModel(
                scanningFeature: ScanningFeature()
            )
        )
        .preferredColorScheme(.dark)
    }
}