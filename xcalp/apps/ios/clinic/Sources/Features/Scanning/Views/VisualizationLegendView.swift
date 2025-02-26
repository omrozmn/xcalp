import SwiftUI

struct VisualizationLegendView: View {
    let mode: VisualizationMode
    let minDepth: Float
    let maxDepth: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(legendTitle)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if mode == .heatmap {
                HeatmapGradient()
            } else {
                DepthGradient()
            }
            
            HStack {
                Text(String(format: "%.1fm", minDepth))
                Spacer()
                Text(String(format: "%.1fm", maxDepth))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
    
    private var legendTitle: String {
        switch mode {
        case .points:
            return "Depth (meters)"
        case .mesh:
            return "Surface Depth"
        case .wireframe:
            return "Wireframe Depth"
        case .heatmap:
            return "Quality Heat Map"
        }
    }
}

private struct DepthGradient: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .red,
                .orange,
                .yellow,
                .green,
                .blue
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 16)
        .cornerRadius(4)
    }
}

private struct HeatmapGradient: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .blue,
                .green,
                .yellow,
                .orange,
                .red
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 16)
        .cornerRadius(4)
        .overlay(
            HStack {
                Text("Low")
                Spacer()
                Text("High")
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
        )
    }
}