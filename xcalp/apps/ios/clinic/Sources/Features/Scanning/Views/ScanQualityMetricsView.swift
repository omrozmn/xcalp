import SwiftUI

struct ScanQualityMetricsView: View {
    let quality: Float
    let pointCount: Int
    let coverage: Float
    let blurAmount: Float
    let isCompensatingBlur: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Overall quality indicator
            QualityIndicator(
                value: quality,
                icon: "gauge",
                title: "Overall Quality",
                description: qualityDescription
            )
            
            HStack(spacing: 20) {
                // Point count indicator
                MetricBox(
                    value: Float(pointCount) / 10000, // Normalize to percentage
                    maxValue: 10000,
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Points",
                    valueLabel: "\(pointCount)"
                )
                
                // Coverage indicator
                MetricBox(
                    value: coverage,
                    maxValue: 1.0,
                    icon: "square.3.layers.3d",
                    title: "Coverage",
                    valueLabel: "\(Int(coverage * 100))%"
                )
            }
            
            // Blur indicator
            if isCompensatingBlur {
                BlurIndicator(blurAmount: blurAmount)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
    
    private var qualityDescription: String {
        switch quality {
        case 0..<0.3:
            return "Poor - Significant improvements needed"
        case 0.3..<0.7:
            return "Fair - Continue scanning to improve"
        case 0.7..<0.9:
            return "Good - Keep going"
        default:
            return "Excellent - Ready to capture"
        }
    }
}

private struct QualityIndicator: View {
    let value: Float
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            
            CircularProgressView(progress: value)
                .frame(width: 60, height: 60)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct MetricBox: View {
    let value: Float
    let maxValue: Float
    let icon: String
    let title: String
    let valueLabel: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            
            Text(title)
                .font(.caption)
            
            Text(valueLabel)
                .font(.headline)
                .foregroundColor(statusColor)
            
            LinearProgressView(progress: value / maxValue)
                .frame(height: 3)
        }
        .frame(width: 80)
    }
    
    private var statusColor: Color {
        let normalizedValue = value / maxValue
        switch normalizedValue {
        case 0..<0.3: return .red
        case 0.3..<0.7: return .yellow
        default: return .green
        }
    }
}

private struct BlurIndicator: View {
    let blurAmount: Float
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "camera.filters")
                Text("Motion Compensation Active")
                    .font(.caption)
            }
            .foregroundColor(.orange)
            
            LinearProgressView(progress: 1 - blurAmount)
                .frame(height: 3)
        }
    }
}

private struct CircularProgressView: View {
    let progress: Float
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
            
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    progress > 0.7 ? Color.green :
                        progress > 0.3 ? Color.yellow : Color.red,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.system(.body, design: .monospaced))
                .bold()
        }
    }
}

private struct LinearProgressView: View {
    let progress: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                Rectangle()
                    .fill(progressColor)
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }
        .cornerRadius(2)
    }
    
    private var progressColor: Color {
        switch progress {
        case 0..<0.3: return .red
        case 0.3..<0.7: return .yellow
        default: return .green
        }
    }
}