import SwiftUI

struct VisualizationControlsView: View {
    @Binding var selectedMode: VisualizationMode
    let quality: Float
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach([
                VisualizationMode.points,
                .mesh,
                .wireframe,
                .heatmap
            ], id: \.self) { mode in
                VisualizationButton(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    quality: quality,
                    action: { selectedMode = mode }
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
}

private struct VisualizationButton: View {
    let mode: VisualizationMode
    let isSelected: Bool
    let quality: Float
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                
                Text(modeName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .white)
            }
            .padding(8)
            .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
            .cornerRadius(8)
        }
    }
    
    private var iconName: String {
        switch mode {
        case .points:
            return "circle.grid.3x3"
        case .mesh:
            return "square.3.stack.3d"
        case .wireframe:
            return "grid"
        case .heatmap:
            return "thermometer"
        }
    }
    
    private var modeName: String {
        switch mode {
        case .points:
            return "Points"
        case .mesh:
            return "Mesh"
        case .wireframe:
            return "Wire"
        case .heatmap:
            return "Heat"
        }
    }
}