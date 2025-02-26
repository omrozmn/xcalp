import SwiftUI

struct ErrorHandlingView: View {
    let error: ScanningError
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    @State private var isShowingDetails = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Error icon and type
            Image(systemName: iconForError(error.type))
                .font(.largeTitle)
                .foregroundColor(colorForError(error.type))
            
            // Error message
            Text(error.message)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            // Recommendation
            Text(error.recommendation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Progress indicators for quality/coverage errors
            if case .qualityLow(let quality) = error.type {
                ProgressIndicator(
                    value: quality,
                    title: "Quality",
                    targetValue: 0.7
                )
            } else if case .insufficientCoverage(let coverage) = error.type {
                ProgressIndicator(
                    value: coverage,
                    title: "Coverage",
                    targetValue: 0.7
                )
            } else if case .motionBlur(let amount) = error.type {
                ProgressIndicator(
                    value: 1.0 - amount,
                    title: "Stability",
                    targetValue: 0.7
                )
            }
            
            // Action buttons
            HStack(spacing: 20) {
                if error.canRetry {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Dismiss")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            // Technical details (collapsible)
            if isShowingDetails {
                TechnicalDetailsView(error: error)
                    .transition(.move(edge: .bottom))
            }
            
            // Show/hide details button
            Button(action: { withAnimation { isShowingDetails.toggle() } }) {
                HStack {
                    Text(isShowingDetails ? "Hide Details" : "Show Details")
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isShowingDetails ? 90 : 0))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    private func iconForError(_ type: ScanningErrorType) -> String {
        switch type {
        case .qualityLow:
            return "exclamationmark.triangle"
        case .insufficientCoverage:
            return "square.3.layers.3d.down.right"
        case .motionBlur:
            return "camera.metering.unknown"
        case .systemResources:
            return "memorychip"
        case .tracking:
            return "location.slash"
        case .lighting:
            return "sun.max"
        case .initialization:
            return "gearshape"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    private func colorForError(_ type: ScanningErrorType) -> Color {
        switch type {
        case .qualityLow, .insufficientCoverage, .motionBlur:
            return .yellow
        case .systemResources, .tracking, .lighting:
            return .orange
        case .initialization, .unknown:
            return .red
        }
    }
}

private struct ProgressIndicator: View {
    let value: Float
    let title: String
    let targetValue: Float
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))%")
            }
            .font(.caption)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                    
                    Rectangle()
                        .fill(value >= targetValue ? Color.green : Color.orange)
                        .frame(width: geometry.size.width * CGFloat(value))
                    
                    // Target indicator
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * CGFloat(targetValue))
                }
            }
            .frame(height: 4)
            .cornerRadius(2)
        }
    }
}

private struct TechnicalDetailsView: View {
    let error: ScanningError
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Technical Details")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Group {
                DetailRow(title: "Error Type", value: String(describing: error.type))
                DetailRow(title: "Can Retry", value: error.canRetry ? "Yes" : "No")
                DetailRow(title: "Has Recovery", value: error.recoveryAction != nil ? "Yes" : "No")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}