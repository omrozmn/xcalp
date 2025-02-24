import Charts
import ComposableArchitecture
import SwiftUI

struct AnalyticsDashboardView: View {
    @StateObject private var viewModel = AnalyticsDashboardViewModel()
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                // Performance Metrics Section
                MetricsCard("Performance") {
                    VStack(spacing: 12) {
                        Chart(viewModel.memoryUsageData.suffix(30)) { item in
                            LineMark(
                                x: .value("Time", item.timestamp),
                                y: .value("Memory (MB)", item.value)
                            )
                            .foregroundStyle(viewModel.isMemoryUsageHigh ? .red : .blue)
                        }
                        .frame(height: 100)
                        
                        MetricRow(
                            title: "Memory Usage",
                            value: "\(viewModel.currentMemoryUsage, specifier: "%.1f") MB",
                            trend: viewModel.memoryTrend
                        )
                        
                        MetricRow(
                            title: "Frame Rate",
                            value: "\(viewModel.currentFrameRate, specifier: "%.1f") FPS",
                            trend: viewModel.frameRateTrend
                        )
                    }
                }
                
                // Scanning Metrics Section
                MetricsCard("Scanning") {
                    VStack(spacing: 12) {
                        Chart(viewModel.scanQualityData) { item in
                            BarMark(
                                x: .value("Quality", item.quality),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(by: .value("Quality", item.quality))
                        }
                        .frame(height: 100)
                        
                        MetricRow(
                            title: "Success Rate",
                            value: "\(viewModel.scanSuccessRate * 100, specifier: "%.1f")%",
                            trend: viewModel.scanSuccessTrend
                        )
                        
                        MetricRow(
                            title: "Avg. Duration",
                            value: "\(viewModel.averageScanTime, specifier: "%.1f")s",
                            trend: viewModel.scanDurationTrend
                        )
                    }
                }
                
                // Security Metrics Section
                MetricsCard("Security") {
                    VStack(spacing: 12) {
                        SecurityStatusView(metrics: viewModel.securityMetrics)
                        
                        Divider()
                        
                        MetricRow(
                            title: "Authentication",
                            value: viewModel.authenticationStatus,
                            trend: viewModel.securityTrend
                        )
                        
                        MetricRow(
                            title: "Encryption",
                            value: viewModel.encryptionStatus,
                            trend: .neutral
                        )
                    }
                }
                
                // Usage Metrics Section
                MetricsCard("Usage Analytics") {
                    VStack(spacing: 12) {
                        Chart(viewModel.templateUsageData) { item in
                            BarMark(
                                x: .value("Template", item.name),
                                y: .value("Count", item.count)
                            )
                        }
                        .frame(height: 100)
                        
                        AnalyticsMetricsView(viewModel: viewModel)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Analytics Dashboard")
        .refreshable {
            await viewModel.refreshData()
        }
        .task {
            await viewModel.startMetricsCollection()
        }
    }
}

struct MetricsCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let trend: MetricTrend
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 4) {
                trend.icon
                    .foregroundColor(trend.color)
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }
}

enum MetricTrend {
    case improving
    case declining
    case neutral
    
    var icon: Image {
        switch self {
        case .improving: return Image(systemName: "arrow.up.right")
        case .declining: return Image(systemName: "arrow.down.right")
        case .neutral: return Image(systemName: "minus")
        }
    }
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .declining: return .red
        case .neutral: return .gray
        }
    }
}
