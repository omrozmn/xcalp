import SwiftUI
import ComposableArchitecture

public struct ScanReviewView: View {
    let store: StoreOf<ScanReviewFeature>
    
    public init(store: StoreOf<ScanReviewFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack {
                SceneView(scanData: viewStore.scanData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                VStack(spacing: 16) {
                    // Quality metrics
                    QualityMetricsView(metrics: viewStore.scanData.meshData.quality)
                    
                    // Export options
                    ExportOptionsView(
                        isExporting: viewStore.binding(
                            get: \.isExporting,
                            send: ScanReviewFeature.Action.setExporting
                        ),
                        selectedFormat: viewStore.binding(
                            get: \.selectedExportFormat,
                            send: ScanReviewFeature.Action.selectExportFormat
                        ),
                        onExport: { viewStore.send(.exportScan) }
                    )
                }
                .padding()
                .background(Material.regular)
            }
            .alert(
                "Export Failed",
                isPresented: viewStore.binding(
                    get: { $0.error != nil },
                    send: ScanReviewFeature.Action.dismissError
                ),
                presenting: viewStore.error
            ) { _ in
                Button("OK") { viewStore.send(.dismissError) }
            } message: { error in
                Text(error.localizedDescription)
            }
            .fileExporter(
                isPresented: viewStore.binding(
                    get: \.showingFileExporter,
                    send: ScanReviewFeature.Action.setShowingFileExporter
                ),
                document: viewStore.exportedDocument,
                contentType: .init(viewStore.selectedExportFormat.contentType),
                defaultFilename: "scan.\(viewStore.selectedExportFormat.fileExtension)"
            ) { result in
                viewStore.send(.handleExportResult(result))
            }
        }
    }
}

private struct QualityMetricsView: View {
    let metrics: MeshQualityData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan Quality")
                .font(.headline)
            
            HStack(spacing: 16) {
                MetricRow(
                    label: "Density",
                    value: metrics.vertexDensity,
                    icon: "chart.bar.fill"
                )
                MetricRow(
                    label: "Smoothness",
                    value: metrics.surfaceSmoothness,
                    icon: "waveform.path.ecg"
                )
                MetricRow(
                    label: "Consistency",
                    value: metrics.normalConsistency,
                    icon: "checkmark.circle.fill"
                )
            }
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: Float
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Label(label, systemImage: icon)
                .font(.caption)
            Text(String(format: "%.1f", value))
                .font(.title3)
                .foregroundColor(qualityColor)
        }
    }
    
    private var qualityColor: Color {
        switch value {
        case 0.8...: return .green
        case 0.6..<0.8: return .yellow
        default: return .red
        }
    }
}

private struct ExportOptionsView: View {
    @Binding var isExporting: Bool
    @Binding var selectedFormat: MeshExportFormat
    let onExport: () -> Void
    
    var body: some View {
        VStack {
            Picker("Export Format", selection: $selectedFormat) {
                Text("OBJ").tag(MeshExportFormat.obj)
                Text("USDZ").tag(MeshExportFormat.usdz)
                Text("PLY").tag(MeshExportFormat.ply)
            }
            .pickerStyle(.segmented)
            
            Button(action: onExport) {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("Export")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
    }
}