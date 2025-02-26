import SwiftUI
import Metal
import MetalKit
import ARKit

public struct ScanningVisualizerView: View {
    let scannedMesh: MTKMesh?
    let quality: QualityAssessment?
    let progress: Double
    @State private var rotationAngle: Double = 0
    @State private var isRotating = false
    
    public var body: some View {
        VStack(spacing: 20) {
            // 3D Mesh Preview
            if let mesh = scannedMesh {
                MetalMeshPreview(mesh: mesh)
                    .frame(height: 300)
                    .rotation3DEffect(
                        .degrees(rotationAngle),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                rotationAngle += value.translation.width
                            }
                    )
            } else {
                ProgressView()
                    .frame(height: 300)
            }
            
            // Quality Indicators
            if let quality = quality {
                QualityVisualizerView(quality: quality)
            }
            
            // Progress Indicator
            ProgressIndicator(progress: progress)
            
            // Scan Controls
            ScanControlsView(isRotating: $isRotating)
        }
        .padding()
        .onChange(of: isRotating) { rotating in
            withAnimation(
                .linear(duration: 4)
                .repeatForever(autoreverses: false)
            ) {
                if rotating {
                    rotationAngle += 360
                }
            }
        }
    }
}

private struct MetalMeshPreview: UIViewRepresentable {
    let mesh: MTKMesh
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = true
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.mesh = mesh
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(mesh: mesh)
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var mesh: MTKMesh
        var renderer: MeshRenderer?
        
        init(mesh: MTKMesh) {
            self.mesh = mesh
            super.init()
            setupRenderer()
        }
        
        func setupRenderer() {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            renderer = try? MeshRenderer(device: device, mesh: mesh)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer?.updateSize(size: size)
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            renderer?.render(
                renderPassDescriptor: renderPassDescriptor,
                drawable: drawable
            )
        }
    }
}

private struct QualityVisualizerView: View {
    let quality: QualityAssessment
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Scan Quality Analysis")
                .font(.headline)
            
            HStack(spacing: 20) {
                QualityMetricView(
                    title: "Surface",
                    value: quality.surfaceCompleteness,
                    threshold: AppConfiguration.Performance.Scanning.minSurfaceCompleteness
                )
                
                QualityMetricView(
                    title: "Detail",
                    value: Double(quality.featurePreservation),
                    threshold: Double(AppConfiguration.Performance.Scanning.minFeaturePreservation)
                )
                
                QualityMetricView(
                    title: "Noise",
                    value: 1.0 - Double(quality.noiseLevel),
                    threshold: 1.0 - Double(AppConfiguration.Performance.Scanning.maxNoiseLevel)
                )
            }
            
            if !quality.isAcceptable {
                ImprovementSuggestionsView(quality: quality)
            }
        }
    }
}

private struct QualityMetricView: View {
    let title: String
    let value: Double
    let threshold: Double
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        value >= threshold ? Color.green : Color.orange,
                        style: StrokeStyle(
                            lineWidth: 8,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 60, height: 60)
        }
    }
}

private struct ProgressIndicator: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Scanning Progress")
                .font(.subheadline)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(.gray.opacity(0.2))
                    
                    Rectangle()
                        .foregroundColor(.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)
            .cornerRadius(4)
            
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct ScanControlsView: View {
    @Binding var isRotating: Bool
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: { isRotating.toggle() }) {
                Image(systemName: isRotating ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            
            Button(action: {}) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title)
            }
        }
    }
}

private struct ImprovementSuggestionsView: View {
    let quality: QualityAssessment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions for Improvement")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(getSuggestions(), id: \.self) { suggestion in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(suggestion)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func getSuggestions() -> [String] {
        var suggestions: [String] = []
        
        if quality.surfaceCompleteness < AppConfiguration.Performance.Scanning.minSurfaceCompleteness {
            suggestions.append("Move around the object to capture all surfaces")
        }
        
        if quality.featurePreservation < AppConfiguration.Performance.Scanning.minFeaturePreservation {
            suggestions.append("Hold the device more steady while scanning")
        }
        
        if quality.noiseLevel > AppConfiguration.Performance.Scanning.maxNoiseLevel {
            suggestions.append("Ensure proper lighting and scan from an optimal distance")
        }
        
        return suggestions
    }
}