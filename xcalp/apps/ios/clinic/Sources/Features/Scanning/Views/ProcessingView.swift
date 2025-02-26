import SwiftUI

public struct ProcessingView: View {

    let progress: Float
    let stage: CaptureProgressManager.CaptureStage?
    
    public var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress) {
                Text(stage?.description ?? "Processing Scan")
                    .font(.headline)
            }
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let stage = stage {
                StageIndicatorView(currentStage: stage)
            }
        }
        .padding()
    }
}

private struct StageIndicatorView: View {
    let currentStage: CaptureProgressManager.CaptureStage
    
    private let allStages: [CaptureProgressManager.CaptureStage] = [
        .preparingCapture,
        .processingDepthData,
        .generatingMesh,
        .optimizingMesh,
        .preparingExport,
        .complete
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(allStages, id: \.description) { stage in
                HStack {
                    Image(systemName: getStageIcon(stage))
                        .foregroundColor(getStageColor(stage))
                    
                    Text(stage.description)
                        .font(.caption)
                        .foregroundColor(getStageColor(stage))
                }
            }
        }
        .padding(.top)
    }
    
    private func getStageIcon(_ stage: CaptureProgressManager.CaptureStage) -> String {
        if stage.progress <= currentStage.progress {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }
    
    private func getStageColor(_ stage: CaptureProgressManager.CaptureStage) -> Color {
        if stage.progress < currentStage.progress {
            return .green
        } else if stage == currentStage {
            return .blue
        } else {
            return .gray
        }
    }
}