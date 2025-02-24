import SwiftUI
import ARKit

struct ScanningOverlayView: View {
    @ObservedObject var feedbackService: ScanningFeedbackService
    
    private let gridColor = Color(.systemBlue).opacity(0.3)
    private let qualityColors: [ScanQualityStatus: Color] = [
        .excellent: .green,
        .good: .blue,
        .insufficient: .yellow,
        .poor: .red,
        .unknown: .gray
    ]
    
    var body: some View {
        ZStack {
            // Reference grid
            GridBackground()
                .stroke(gridColor, lineWidth: 1)
            
            // Quality indicator
            QualityIndicatorView(status: feedbackService.qualityStatus)
                .frame(width: 60, height: 60)
                .position(x: 40, y: 40)
            
            // Guidance messages
            GuidanceMessagesView(messages: feedbackService.guidanceMessages)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 100)
            
            // Processing status
            if case .processing(let progress) = feedbackService.processingStatus {
                ProcessingIndicatorView(progress: progress)
            }
        }
    }
}

private struct GridBackground: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stepSize: CGFloat = 50
        
        // Vertical lines
        for x in stride(from: 0, to: rect.width, by: stepSize) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Horizontal lines
        for y in stride(from: 0, to: rect.height, by: stepSize) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

private struct QualityIndicatorView: View {
    let status: ScanQualityStatus
    
    var body: some View {
        Circle()
            .fill(qualityColors[status] ?? .gray)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(radius: 2)
    }
}

private struct GuidanceMessagesView: View {
    let messages: [GuidanceMessage]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(messages) { message in
                GuidanceMessageRow(message: message)
                    .transition(.opacity.combined(with: .slide))
            }
        }
        .animation(.easeInOut, value: messages)
    }
}

private struct GuidanceMessageRow: View {
    let message: GuidanceMessage
    
    var body: some View {
        HStack {
            messageIcon
            Text(message.text)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(messageBackground)
        .cornerRadius(20)
    }
    
    private var messageIcon: some View {
        switch message.type {
        case .info:
            return Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
        case .success:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .qualityWarning:
            return Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
        case .error:
            return Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    private var messageBackground: some View {
        Color.black.opacity(0.7)
    }
}

private struct ProcessingIndicatorView: View {
    let progress: Float
    
    var body: some View {
        VStack {
            ProgressView(value: progress)
                .progressViewStyle(CircularProgressViewStyle())
            Text("\(Int(progress * 100))%")
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}