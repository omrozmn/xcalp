import SwiftUI
import SceneKit
import ComposableArchitecture

public struct InteractiveStudioFeature: Reducer {
    public struct State: Equatable {
        var currentTool: StudioTool = .view
        var meshData: MeshData?
        var selectedRegions: Set<UUID> = []
        var measurements: [Measurement] = []
        var isProcessing: Bool = false
        var error: String?
        
        public init() {}
    }
    
    public enum Action: Equatable {
        case setTool(StudioTool)
        case selectRegion(UUID)
        case deselectRegion(UUID)
        case addMeasurement(Measurement)
        case removeMeasurement(UUID)
        case processMesh
        case processCompleted(Result<MeshData, Error>)
        case setError(String?)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setTool(tool):
                state.currentTool = tool
                return .none
                
            case let .selectRegion(id):
                state.selectedRegions.insert(id)
                return .none
                
            case let .deselectRegion(id):
                state.selectedRegions.remove(id)
                return .none
                
            case let .addMeasurement(measurement):
                state.measurements.append(measurement)
                return .none
                
            case let .removeMeasurement(id):
                state.measurements.removeAll { $0.id == id }
                return .none
                
            case .processMesh:
                state.isProcessing = true
                return .none
                
            case let .processCompleted(.success(meshData)):
                state.meshData = meshData
                state.isProcessing = false
                return .none
                
            case .processCompleted(.failure):
                state.isProcessing = false
                state.error = "Failed to process mesh"
                return .none
                
            case let .setError(error):
                state.error = error
                return .none
            }
        }
    }
}

public struct InteractiveStudioView: View {
    let store: StoreOf<InteractiveStudioFeature>
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            HStack(spacing: 0) {
                // Tools Panel
                ToolsPanel(currentTool: viewStore.binding(
                    get: \.currentTool,
                    send: InteractiveStudioFeature.Action.setTool
                ))
                
                // Main Workspace
                ZStack {
                    WorkspaceView(
                        meshData: viewStore.meshData,
                        selectedRegions: viewStore.selectedRegions,
                        currentTool: viewStore.currentTool,
                        onRegionSelected: { id in
                            viewStore.send(.selectRegion(id))
                        }
                    )
                    
                    if viewStore.isProcessing {
                        ProgressView("Processing...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial)
                    }
                }
                
                // Properties Panel
                PropertiesPanel(
                    selectedRegions: viewStore.selectedRegions,
                    measurements: viewStore.measurements,
                    onMeasurementAdded: { measurement in
                        viewStore.send(.addMeasurement(measurement))
                    },
                    onMeasurementRemoved: { id in
                        viewStore.send(.removeMeasurement(id))
                    }
                )
            }
            .alert(
                "Error",
                isPresented: .constant(viewStore.error != nil),
                actions: {
                    Button("OK") {
                        viewStore.send(.setError(nil))
                    }
                },
                message: {
                    Text(viewStore.error ?? "")
                }
            )
        }
    }
}

// MARK: - Supporting Views
private struct ToolsPanel: View {
    @Binding var currentTool: StudioTool
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(StudioTool.allCases) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: tool == currentTool,
                    action: { currentTool = tool }
                )
            }
        }
        .padding()
        .frame(width: 80)
        .background(BrandConstants.Colors.darkNavy)
    }
}

private struct ToolButton: View {
    let tool: StudioTool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? BrandConstants.Colors.vibrantBlue : .white)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(
                    isSelected ?
                    BrandConstants.Colors.lightSilver :
                    Color.clear
                )
                .cornerRadius(8)
        }
    }
}

private struct WorkspaceView: View {
    let meshData: MeshData?
    let selectedRegions: Set<UUID>
    let currentTool: StudioTool
    let onRegionSelected: (UUID) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let meshData = meshData {
                    SceneView(
                        scene: createScene(with: meshData),
                        options: [.allowsCameraControl, .autoenablesDefaultLighting]
                    )
                } else {
                    ContentUnavailableView(
                        "No Scan Data",
                        systemImage: "cube.transparent",
                        description: Text("Import or capture a 3D scan to begin")
                    )
                }
                
                // Tool-specific overlays
                switch currentTool {
                case .measure:
                    MeasurementOverlay()
                case .brush:
                    BrushingOverlay()
                case .region:
                    RegionEditingOverlay(
                        selectedRegions: selectedRegions,
                        onRegionSelected: onRegionSelected
                    )
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private func createScene(with meshData: MeshData) -> SCNScene {
        let scene = SCNScene()
        // Convert MeshData to SCNGeometry and set up scene
        // Implementation details...
        return scene
    }
}

private struct PropertiesPanel: View {
    let selectedRegions: Set<UUID>
    let measurements: [Measurement]
    let onMeasurementAdded: (Measurement) -> Void
    let onMeasurementRemoved: (UUID) -> Void
    
    var body: some View {
        VStack {
            Text("Properties")
                .xcalpText(.h2)
                .padding()
            
            if !selectedRegions.isEmpty {
                RegionPropertiesView(regions: selectedRegions)
            }
            
            Divider()
            
            MeasurementsListView(
                measurements: measurements,
                onMeasurementAdded: onMeasurementAdded,
                onMeasurementRemoved: onMeasurementRemoved
            )
        }
        .frame(width: 300)
        .background(Color.white)
        .xcalpCard()
    }
}

// MARK: - Models
public enum StudioTool: String, CaseIterable, Identifiable {
    case view
    case measure
    case brush
    case region
    case analyze
    
    public var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .view: "eye"
        case .measure: "ruler"
        case .brush: "paintbrush"
        case .region: "square.dashed"
        case .analyze: "chart.bar"
        }
    }
}

struct Measurement: Identifiable, Equatable {
    let id: UUID
    let type: MeasurementType
    let value: Float
    let unit: String
    
    enum MeasurementType {
        case distance
        case area
        case angle
        case density
    }
}