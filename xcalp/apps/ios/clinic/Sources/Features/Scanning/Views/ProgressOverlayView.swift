import SwiftUI

struct ProgressOverlayView: View {
    let progress: Float
    let quality: Float
    let isRecovering: Bool
    let guidanceMessage: String
    let captureStage: CaptureProgressManager.CaptureStage?
    
    var body: some View {
        VStack(spacing: 16) {
            // Quality indicator
            QualityGauge(quality: quality)
                .frame(width: 120, height: 120)
            
            if isRecovering {
                RecoveryProgressView(progress: progress)
            } else {
                // Progress bars
                VStack(alignment: .leading, spacing: 8) {
                    ProgressBar(
                        progress: progress,
                        label: captureStage?.description ?? "Scanning",
                        color: progressColor
                    )
                    
                    ProgressBar(
                        progress: quality,
                        label: "Quality",
                        color: qualityColor
                    )
                }
                .padding(.horizontal)
            }
            
            // Guidance message
            if !guidanceMessage.isEmpty {
                Text(guidanceMessage)
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private var progressColor: Color {
        if isRecovering {
            return .orange
        }
        return progress > 0.7 ? .green : .blue
    }
    
    private var qualityColor: Color {
        switch quality {
        case 0..<0.3: return .red
        case 0.3..<0.7: return .orange
        default: return .green
        }
    }
}

private struct QualityGauge: View {
    let quality: Float
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.secondary.opacity(0.2),
                    lineWidth: 10
                )
            
            Circle()
                .trim(from: 0, to: CGFloat(quality))
                .stroke(
                    qualityColor,
                    style: StrokeStyle(
                        lineWidth: 10,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: quality)
            
            VStack {
                Text("\(Int(quality * 100))%")
                    .font(.title2)
                    .bold()
                
                Text("Quality")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var qualityColor: Color {
        switch quality {
        case 0..<0.3: return .red
        case 0.3..<0.7: return .orange
        default: return .green
        }
    }
}

private struct ProgressBar: View {
    let progress: Float
    let label: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(progress))
                }
                .cornerRadius(4)
                .animation(.easeInOut, value: progress)
            }
            .frame(height: 8)
        }
    }
}

private struct RecoveryProgressView: View {
    let progress: Float
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress) {
                Text("Recovering scan...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}