import SwiftUI

struct SystemStatusOverlay: View {
    let status: SystemStatus
    
    var body: some View {
        if case .optimal = status {
            EmptyView()
        } else {
            statusBanner
        }
    }
    
    private var statusBanner: some View {
        HStack(spacing: 8) {
            statusIcon
            
            Text(statusMessage)
                .font(.footnote)
                .foregroundColor(statusColor)
            
            Spacer()
            
            if case .warning = status {
                Button(action: {}) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusBackgroundColor)
        .transition(.move(edge: .top))
    }
    
    private var statusIcon: some View {
        Image(systemName: statusIconName)
            .foregroundColor(statusColor)
    }
    
    private var statusIconName: String {
        switch status {
        case .optimal:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }
    
    private var statusMessage: String {
        switch status {
        case .optimal:
            return ""
        case .warning(let message), .critical(let message):
            return message
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .optimal:
            return .green
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }
    
    private var statusBackgroundColor: Color {
        switch status {
        case .optimal:
            return .clear
        case .warning:
            return .yellow.opacity(0.2)
        case .critical:
            return .red.opacity(0.2)
        }
    }
}