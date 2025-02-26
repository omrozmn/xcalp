import Combine
import RealityKit
import SwiftUI
import ARKit

public struct ScanningView: View {
    @StateObject private var viewModel: ScanningPreviewViewModel
    @Environment(\.accessibilityEnabled) var accessibilityEnabled
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    @State private var showingSessionManagement = false
    @State private var showingExportOptions = false
    
    public init(scanningFeature: ScanningFeature) {
        _viewModel = StateObject(wrappedValue: ScanningPreviewViewModel(scanningFeature: scanningFeature))
    }
    
    public var body: some View {
        ZStack {
            // AR Scene View with particle effects
            ZStack {
                ARViewContainer()
                
                if viewModel.showingGuide {
                    ScanningParticleSystem(
                        quality: viewModel.scanningQuality,
                        coverage: viewModel.coverage,
                        isScanning: true
                    )
                    .opacity(0.5)
                }
            }
            
            // Main scanning interface with animated transitions
            AnimatedTransitionView(state: .scanning) {
                ComprehensiveScanningPreviewView(viewModel: viewModel)
            }
            
            // Floating quality indicators
            if viewModel.shouldShowMetrics {
                VStack {
                    HStack {
                        FloatingQualityIndicator(
                            quality: viewModel.scanningQuality,
                            label: "Quality"
                        )
                        
                        FloatingQualityIndicator(
                            quality: viewModel.coverage,
                            label: "Coverage"
                        )
                    }
                    .padding(.top, 100)
                    
                    Spacer()
                }
            }
            
            // Coverage visualization
            if viewModel.shouldShowCoverageMap {
                VStack {
                    Spacer()
                    
                    AnimatedCoverageView(
                        coverage: viewModel.coverage,
                        regions: [] // Will be populated with actual coverage data
                    )
                    .frame(height: 150)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingSessionManagement) {
            SessionManagementView()
        }
        .sheet(isPresented: $showingExportOptions) {
            // Export options view would be implemented here
        }
        .onChange(of: viewModel.scanningQuality) { quality in
            provideDynamicFeedback(quality: quality)
        }
        .onChange(of: viewModel.coverage) { coverage in
            provideDynamicFeedback(coverage: coverage)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingSessionManagement.toggle() }) {
                    Image(systemName: "square.stack.3d.up")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingExportOptions.toggle() }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!viewModel.canCapture)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func provideDynamicFeedback(
        quality: Float? = nil,
        coverage: Float? = nil
    ) {
        if let quality = quality {
            HapticFeedback.shared.playQualityFeedback(quality)
        }
        
        if let coverage = coverage {
            HapticFeedback.shared.playCoverageFeedback(coverage)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ScanningView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScanningView(scanningFeature: ScanningFeature())
        }
    }
}