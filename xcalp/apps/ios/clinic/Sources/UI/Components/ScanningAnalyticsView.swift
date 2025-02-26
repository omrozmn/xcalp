import SwiftUI
import Charts

public struct ScanningAnalyticsView: View {
    let metrics: [ScanningMetric]
    let quality: QualityAssessment?
    
    public var body: some View {
        VStack(spacing: 16) {
            // Quality indicators
            if let quality = quality {
                QualityMetricsView(quality: quality)
            }
            
            // Performance charts
            MetricsChartView(metrics: metrics)
            
            // Status indicators
            StatusIndicatorsView(metrics: metrics)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

private struct QualityMetricsView: View {
    let quality: QualityAssessment
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Scan Quality")
                .font(.headline)
            
            HStack(spacing: 20) {
                QualityIndicator(
                    title: "Density",
                    value: quality.pointDensity,
                    threshold: AppConfiguration.Performance.Scanning.minPointDensity
                )
                
                QualityIndicator(
                    title: "Coverage",
                    value: Float(quality.surfaceCompleteness),
                    threshold: Float(AppConfiguration.Performance.Scanning.minSurfaceCompleteness)
                )
                
                QualityIndicator(
                    title: "Detail",
                    value: quality.featurePreservation,
                    threshold: AppConfiguration.Performance.Scanning.minFeaturePreservation
                )
            }
        }
    }
}

private struct MetricsChartView: View {
    let metrics: [ScanningMetric]
    
    var body: some View {
        Chart(metrics) { metric in
            LineMark(
                x: .value("Time", metric.timestamp),
                y: .value("Value", metric.value)
            )
            .foregroundStyle(by: .value("Metric", metric.name))
        }
        .chartForegroundStyleScale([
            "CPU": .red,
            "Memory": .blue,
            "GPU": .green,
            "FPS": .orange
        ])
        .frame(height: 200)
    }
}

private struct StatusIndicatorsView: View {
    let metrics: [ScanningMetric]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(getLatestMetrics(), id: \.name) { metric in
                StatusIndicator(
                    title: metric.name,
                    value: String(format: "%.1f", metric.value),
                    unit: metric.unit,
                    status: getStatus(for: metric)
                )
            }
        }
    }
    
    private func getLatestMetrics() -> [ScanningMetric] {
        // Group by name and get latest for each
        Dictionary(grouping: metrics, by: \.name)
            .compactMap { $0.value.max(by: { $0.timestamp < $1.timestamp }) }
    }
    
    private func getStatus(for metric: ScanningMetric) -> StatusLevel {
        let thresholds = AppConfiguration.Performance.Thresholds.self
        
        switch metric.name {
        case "CPU":
            return metric.value <= thresholds.maxCPUUsage ? .good : .warning
        case "Memory":
            return metric.value <= Double(thresholds.maxMemoryUsage) ? .good : .warning
        case "GPU":
            return metric.value <= thresholds.maxGPUUtilization ? .good : .warning
        case "FPS":
            return metric.value >= thresholds.minFrameRate ? .good : .warning
        default:
            return .normal
        }
    }
}

private struct QualityIndicator: View {
    let title: String
    let value: Float
    let threshold: Float
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
            
            CircularProgressView(
                progress: Double(value),
                threshold: Double(threshold),
                color: value >= threshold ? .green : .orange
            )
            .frame(width: 60, height: 60)
            
            Text(String(format: "%.1f", value))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct StatusIndicator: View {
    let title: String
    let value: String
    let unit: String
    let status: StatusLevel
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                
                Text(value)
                    .font(.subheadline)
                
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

private struct CircularProgressView: View {
    let progress: Double
    let threshold: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(
                    lineWidth: 4,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

// MARK: - Supporting Types

public struct ScanningMetric: Identifiable {
    public let id = UUID()
    public let name: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
}

public enum StatusLevel {
    case good
    case normal
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .good: return .green
        case .normal: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}