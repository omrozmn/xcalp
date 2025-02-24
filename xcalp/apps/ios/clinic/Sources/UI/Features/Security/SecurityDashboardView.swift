import ComposableArchitecture
import SwiftUI

struct SecurityDashboardView: View {
    @StateObject private var viewModel = SecurityDashboardViewModel()
    
    var body: some View {
        List {
            Section("Access Security") {
                AccessAttemptsView(attempts: viewModel.metrics.accessAttempts)
            }
            
            Section("Encryption Status") {
                EncryptionStatusView(status: viewModel.metrics.encryptionStatus)
            }
            
            Section("Audit Trail") {
                AuditStatusView(status: viewModel.metrics.auditStatus)
            }
            
            Section("HIPAA Compliance") {
                ComplianceStatusView(status: viewModel.metrics.complianceStatus)
            }
        }
        .navigationTitle("Security Dashboard")
        .refreshable {
            await viewModel.refreshMetrics()
        }
    }
}

private struct AccessAttemptsView: View {
    let attempts: AccessAttempts
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: "Successful", value: "\(attempts.successful)")
                .foregroundColor(.green)
            
            MetricRow(title: "Failed", value: "\(attempts.failed)")
                .foregroundColor(.red)
            
            MetricRow(title: "Suspicious", value: "\(attempts.suspicious)")
                .foregroundColor(.orange)
            
            if !attempts.blockedIPs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocked IPs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(attempts.blockedIPs, id: \.self) { ip in
                        Text(ip)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

private struct EncryptionStatusView: View {
    let status: EncryptionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: "Algorithm", value: status.algorithm)
            
            MetricRow(title: "Key Strength", value: "\(status.keyStrength) bits")
            
            MetricRow(
                title: "Last Rotation",
                value: status.lastKeyRotation.formatted(date: .abbreviated, time: .shortened)
            )
            
            MetricRow(
                title: "Next Rotation",
                value: "\(status.daysUntilNextRotation) days"
            )
            .foregroundColor(status.daysUntilNextRotation < 7 ? .orange : .primary)
        }
    }
}

private struct AuditStatusView: View {
    let status: AuditStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: "Total Entries", value: "\(status.totalEntries)")
            
            MetricRow(
                title: "Last Audit",
                value: status.lastAuditDate.formatted(date: .abbreviated, time: .shortened)
            )
            
            if status.missingEntries > 0 {
                MetricRow(title: "Missing Entries", value: "\(status.missingEntries)")
                    .foregroundColor(.red)
            }
            
            if !status.integrityIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Integrity Issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(status.integrityIssues, id: \.self) { issue in
                        Text(issue)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

private struct ComplianceStatusView: View {
    let status: ComplianceStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: "Status", value: status.overallStatus.rawValue)
                .foregroundColor(statusColor)
            
            if !status.violations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Violations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(status.violations, id: \.self) { violation in
                        Text(violation)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            if !status.requiredActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required Actions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(status.requiredActions, id: \.self) { action in
                        Text(action)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    private var statusColor: Color {
        switch status.overallStatus {
        case .compliant:
            return .green
        case .mostlyCompliant:
            return .yellow
        case .needsAttention:
            return .orange
        case .nonCompliant:
            return .red
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

@MainActor
class SecurityDashboardViewModel: ObservableObject {
    @Published private(set) var metrics = SecurityMetrics(
        timestamp: Date(),
        accessAttempts: AccessAttempts(),
        encryptionStatus: EncryptionStatus(
            keyStrength: 256,
            lastKeyRotation: Date(),
            daysUntilNextRotation: 90,
            algorithm: "AES-256-GCM"
        ),
        auditStatus: AuditStatus(),
        complianceStatus: ComplianceStatus()
    )
    
    private let dashboard = SecurityMetricsDashboard.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        dashboard.metricsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                self?.metrics = metrics
            }
            .store(in: &cancellables)
    }
    
    func refreshMetrics() async {
        await dashboard.refreshMetrics()
    }
}
