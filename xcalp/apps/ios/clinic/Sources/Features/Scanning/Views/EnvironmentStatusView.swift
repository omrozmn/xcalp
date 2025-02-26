import SwiftUI

struct EnvironmentStatusView: View {
    let validationResult: ValidationResult
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Status header
            HStack {
                statusIcon
                    .font(.title2)
                
                Text(validationResult.isValid ? "Environment Ready" : "Environment Issues")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingDetails.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
            }
            .foregroundColor(.white)
            
            if showingDetails {
                VStack(alignment: .leading, spacing: 8) {
                    // Quality meters
                    QualityMeter(
                        label: "Lighting",
                        value: validationResult.lightingQuality
                    )
                    
                    QualityMeter(
                        label: "Stability",
                        value: validationResult.motionStability
                    )
                    
                    QualityMeter(
                        label: "Surface",
                        value: validationResult.surfaceQuality
                    )
                    
                    // Issues list
                    if !validationResult.environmentIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Issues to Address:")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            
                            ForEach(validationResult.environmentIssues, id: \.description) { issue in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(issueColor(for: issue))
                                    
                                    Text(issue.description)
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .animation(.spring(), value: showingDetails)
    }
    
    private var statusIcon: some View {
        Image(systemName: validationResult.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundColor(validationResult.isValid ? .green : .orange)
    }
    
    private func issueColor(for issue: EnvironmentIssue) -> Color {
        switch issue.priority {
        case 5:
            return .red
        case 4:
            return .orange
        default:
            return .yellow
        }
    }
}

struct QualityMeter: View {
    let label: String
    let value: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                    
                    Rectangle()
                        .fill(meterColor)
                        .frame(width: geometry.size.width * CGFloat(value))
                }
            }
            .frame(height: 4)
            .cornerRadius(2)
        }
    }
    
    private var meterColor: Color {
        switch value {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .orange
        default:
            return .green
        }
    }
}

// Preview provider
#if DEBUG
struct EnvironmentStatusView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            EnvironmentStatusView(
                validationResult: ValidationResult(
                    isValid: false,
                    lightingQuality: 0.7,
                    motionStability: 0.4,
                    surfaceQuality: 0.9,
                    environmentIssues: [
                        .excessiveMotion,
                        .reflectiveSurface
                    ]
                )
            )
            .padding()
        }
        .ignoresSafeArea()
    }
}
#endif