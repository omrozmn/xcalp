import SwiftUI

struct SpeedGaugeView: View {
    let currentSpeed: Float
    let optimalSpeed: Float
    let guidance: String
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Speed gauge
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 60, height: 60)
                
                // Speed indicator
                Circle()
                    .trim(from: 0, to: CGFloat(min(currentSpeed, 1.5) / 1.5))
                    .stroke(speedColor, style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    ))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                // Optimal speed marker
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 12)
                    .offset(y: -30)
                    .rotationEffect(.degrees(240 * Double(optimalSpeed / 1.5) - 30))
                
                // Speed value
                Text("\(Int(currentSpeed * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(speedColor.opacity(0.3), lineWidth: 2)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0 : 1)
            )
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                value: isAnimating
            )
            
            // Speed label
            Text("Speed")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Guidance message
            Text(guidance)
                .font(.caption)
                .foregroundColor(speedColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 150)
                .opacity(shouldShowGuidance ? 1 : 0)
                .animation(.easeInOut, value: guidance)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .onAppear {
            isAnimating = shouldAnimate
        }
        .onChange(of: currentSpeed) { _ in
            isAnimating = shouldAnimate
        }
    }
    
    private var speedColor: Color {
        if currentSpeed > optimalSpeed * 1.2 {
            return .red
        } else if currentSpeed < optimalSpeed * 0.8 {
            return .yellow
        } else {
            return .green
        }
    }
    
    private var shouldShowGuidance: Bool {
        return abs(currentSpeed - optimalSpeed) > 0.2
    }
    
    private var shouldAnimate: Bool {
        return currentSpeed > optimalSpeed * 1.2
    }
    
    private var accessibilityDescription: String {
        let speedStatus: String
        if currentSpeed > optimalSpeed * 1.2 {
            speedStatus = "Too fast"
        } else if currentSpeed < optimalSpeed * 0.8 {
            speedStatus = "Too slow"
        } else {
            speedStatus = "Optimal speed"
        }
        
        return "Scanning speed: \(speedStatus). \(guidance)"
    }
}

#if DEBUG
struct SpeedGaugeView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            SpeedGaugeView(
                currentSpeed: 0.8,
                optimalSpeed: 0.7,
                guidance: "Good scanning speed"
            )
        }
        .frame(width: 200, height: 200)
        .previewLayout(.sizeThatFits)
    }
}