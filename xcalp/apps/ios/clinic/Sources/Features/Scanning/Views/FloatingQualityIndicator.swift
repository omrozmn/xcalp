import SwiftUI

struct FloatingQualityIndicator: View {
    let quality: Float
    let label: String
    @State private var isAnimating = false
    @State private var wave1Offset: CGFloat = 0
    @State private var wave2Offset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(qualityColor.opacity(0.3))
                .blur(radius: 10)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
            
            // Wave effect
            WaveShape(offset: wave1Offset, amplitude: 5)
                .fill(qualityColor.opacity(0.6))
                .mask(Circle())
            
            WaveShape(offset: wave2Offset, amplitude: 3)
                .fill(qualityColor.opacity(0.8))
                .mask(Circle())
            
            // Quality value
            VStack(spacing: 4) {
                Text("\(Int(quality * 100))%")
                    .font(.system(.title3, design: .rounded))
                    .bold()
                
                Text(label)
                    .font(.caption2)
                    .opacity(0.8)
            }
            .foregroundColor(.white)
        }
        .frame(width: 80, height: 80)
        .modifier(FloatingTransition())
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
            
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                wave1Offset = 360
            }
            
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                wave2Offset = -360
            }
        }
    }
    
    private var qualityColor: Color {
        switch quality {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .orange
        default:
            return .green
        }
    }
}

struct WaveShape: Shape {
    var offset: CGFloat
    var amplitude: CGFloat
    
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2
        
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / width
            let sine = sin(relativeX * .pi * 4 + offset * .pi / 180)
            let y = midHeight + sine * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

#if DEBUG
struct FloatingQualityIndicator_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            FloatingQualityIndicator(
                quality: 0.85,
                label: "Quality"
            )
        }
        .frame(width: 200, height: 200)
        .previewLayout(.sizeThatFits)
    }
}