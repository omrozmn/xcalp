import SwiftUI

struct PerformanceMetricsView: View {
    let metrics: ScanningMetrics
    @State private var isExpanded = false
    @Environment(\.sizeCategory) var sizeCategory
    @Environment(\.accessibilityEnabled) var accessibilityEnabled
    
    var body: some View {
        VStack(spacing: 12) {
            // Performance summary button
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: metrics.isPerformanceAcceptable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(metrics.isPerformanceAcceptable ? .green : .orange)
                        .accessibilityHidden(true)
                    
                    Text("Performance Metrics")
                        .font(.subheadline)
                        .dynamicTypeSize(...(.accessibility3))
                    
                    Spacer()
                    
                    Text("\(Int(metrics.fps)) FPS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Frame rate \(Int(metrics.fps)) frames per second")
                    
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") metrics")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if isExpanded {
                // Use adaptive layout based on size category
                if sizeCategory >= .accessibilityLarge {
                    AccessibleMetricsLayout(metrics: metrics)
                } else {
                    StandardMetricsLayout(metrics: metrics)
                }
            }
        }
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
    
    private var accessibilityLabel: String {
        let status = metrics.isPerformanceAcceptable ? "Performance optimal" : "Performance needs attention"
        return "\(status). \(Int(metrics.fps)) frames per second"
    }
}

private struct AccessibleMetricsLayout: View {
    let metrics: ScanningMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricRow(
                title: "CPU Usage",
                value: String(format: "%.1f%%", metrics.cpuUsage * 100),
                icon: "cpu"
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CPU usage \(Int(metrics.cpuUsage * 100)) percent")
            
            MetricRow(
                title: "Memory",
                value: String(format: "%.1f%%", metrics.memoryUsage * 100),
                icon: "memorychip"
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Memory usage \(Int(metrics.memoryUsage * 100)) percent")
            
            MetricRow(
                title: "Battery",
                value: String(format: "%.0f%%", metrics.batteryLevel * 100),
                icon: "battery.100"
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery level \(Int(metrics.batteryLevel * 100)) percent")
            
            if !metrics.isPerformanceAcceptable {
                RecommendationsView(metrics: metrics)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(recommendationsLabel)
            }
        }
        .padding()
    }
    
    private var recommendationsLabel: String {
        let recommendations = getPerformanceRecommendations()
        return "Performance recommendations: \(recommendations.joined(separator: ". "))"
    }
}

private struct StandardMetricsLayout: View {
    let metrics: ScanningMetrics
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary metrics
            HStack {
                MetricCard(
                    title: "CPU",
                    value: String(format: "%.1f%%", metrics.cpuUsage * 100),
                    icon: "cpu",
                    color: colorForUsage(metrics.cpuUsage)
                )
                
                MetricCard(
                    title: "Memory",
                    value: String(format: "%.1f%%", metrics.memoryUsage * 100),
                    icon: "memorychip",
                    color: colorForUsage(metrics.memoryUsage)
                )
                
                MetricCard(
                    title: "Battery",
                    value: String(format: "%.0f%%", metrics.batteryLevel * 100),
                    icon: "battery.100",
                    color: colorForBattery(metrics.batteryLevel)
                )
            }
            
            // Secondary metrics
            VStack(spacing: 8) {
                MetricRow(
                    title: "Points/sec",
                    value: "\(metrics.pointsPerSecond)",
                    icon: "point.3.filled.connected.trianglepath.dotted"
                )
                
                MetricRow(
                    title: "Latency",
                    value: String(format: "%.1f ms", metrics.latency * 1000),
                    icon: "clock"
                )
                
                MetricRow(
                    title: "Thermal",
                    value: thermalStateDescription(metrics.thermalState),
                    icon: "thermometer",
                    color: colorForThermalState(metrics.thermalState)
                )
            }
            
            if !metrics.isPerformanceAcceptable {
                Text("Performance Recommendations")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                ForEach(getPerformanceRecommendations(), id: \.self) { recommendation in
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text(recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// Update MetricCard for better accessibility
private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .accessibilityHidden(true)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .dynamicTypeSize(...(.accessibility2))
            
            Text(value)
                .font(.caption)
                .bold()
                .foregroundColor(color)
                .dynamicTypeSize(...(.accessibility2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// Add new view for recommendations
private struct RecommendationsView: View {
    let metrics: ScanningMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.caption)
                .foregroundColor(.secondary)
                .dynamicTypeSize(...(.accessibility2))
            
            ForEach(getPerformanceRecommendations(), id: \.self) { recommendation in
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    
                    Text(recommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .dynamicTypeSize(...(.accessibility2))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(recommendation)
            }
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .white
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(color)
        }
    }
}

private func colorForUsage(_ value: Double) -> Color {
    switch value {
    case 0..<0.6: return .green
    case 0.6..<0.8: return .yellow
    default: return .red
    }
}

private func colorForBattery(_ level: Float) -> Color {
    switch level {
    case 0..<0.2: return .red
    case 0.2..<0.4: return .orange
    default: return .green
    }
}

private func colorForThermalState(_ state: ProcessInfo.ThermalState) -> Color {
    switch state {
    case .nominal: return .green
    case .fair: return .yellow
    case .serious: return .orange
    case .critical: return .red
    @unknown default: return .gray
    }
}

private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "Normal"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Critical"
    @unknown default: return "Unknown"
    }
}

private func getPerformanceRecommendations() -> [String] {
    var recommendations: [String] = []
    
    if metrics.fps < 30 {
        recommendations.append("Frame rate is low - try reducing background apps")
    }
    
    if metrics.memoryUsage > 0.8 {
        recommendations.append("High memory usage - consider clearing app cache")
    }
    
    if metrics.cpuUsage > 0.9 {
        recommendations.append("High CPU usage - avoid intensive background tasks")
    }
    
    if metrics.thermalState == .serious || metrics.thermalState == .critical {
        recommendations.append("Device is running hot - take a short break")
    }
    
    if metrics.latency > 0.1 {
        recommendations.append("High processing latency - simplify scan area")
    }
    
    return recommendations
}