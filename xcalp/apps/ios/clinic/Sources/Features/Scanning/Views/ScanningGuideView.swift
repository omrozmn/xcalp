import SwiftUI

struct ScanningGuideView: View {
    let scanningQuality: Float
    let coverage: Float
    let hints: [OptimizationHint]
    let guideMessage: String
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Scanning focus area guide
                RoundedRectangle(cornerRadius: 12)
                    .stroke(qualityColor, lineWidth: 2)
                    .frame(
                        width: geometry.size.width * 0.8,
                        height: geometry.size.width * 0.8
                    )
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .opacity(isAnimating ? 0.8 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                
                // Movement guide arrows
                if let highPriorityHint = hints.first(where: { $0.priority >= 4 }) {
                    MovementGuideArrows(hint: highPriorityHint)
                        .opacity(0.8)
                }
                
                // Coverage indicators
                CoverageIndicators(
                    coverage: coverage,
                    size: geometry.size
                )
                
                // Quality indicator
                QualityIndicator(quality: scanningQuality)
                    .position(
                        x: geometry.size.width - 50,
                        y: 50
                    )
                
                // Guide message
                if !guideMessage.isEmpty {
                    Text(guideMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height - 100
                        )
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private var qualityColor: Color {
        switch scanningQuality {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .yellow
        default:
            return .green
        }
    }
}

private struct MovementGuideArrows: View {
    let hint: OptimizationHint
    @State private var offsetMultiplier: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Show different arrow patterns based on the hint
            Group {
                if hint.title.contains("Pattern") {
                    // Side-to-side scanning guide
                    HStack(spacing: 40) {
                        ForEach(0..<3) { _ in
                            VStack(spacing: 20) {
                                Image(systemName: "arrow.up")
                                Image(systemName: "arrow.down")
                            }
                        }
                    }
                } else if hint.title.contains("Gaps") {
                    // Circular motion guide
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "arrow.clockwise")
                                .font(.title)
                        )
                } else {
                    // Default movement guide
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.largeTitle)
                }
            }
            .foregroundColor(.white)
            .offset(x: 5 * offsetMultiplier, y: 0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: offsetMultiplier
            )
        }
        .onAppear {
            offsetMultiplier = -1.0
        }
    }
}

private struct CoverageIndicators: View {
    let coverage: Float
    let size: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // Create coverage indicator segments
                let radius = min(geometry.size.width, geometry.size.height) * 0.45
                let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
                let segments = 36
                let coveredSegments = Int(Float(segments) * coverage)
                
                for i in 0..<segments {
                    let angle = Double(i) * 2 * .pi / Double(segments)
                    let nextAngle = Double(i + 1) * 2 * .pi / Double(segments)
                    
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .init(radians: angle),
                        endAngle: .init(radians: nextAngle),
                        clockwise: false
                    )
                }
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            // Covered area
            Path { path in
                let radius = min(geometry.size.width, geometry.size.height) * 0.45
                let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
                let segments = 36
                let coveredSegments = Int(Float(segments) * coverage)
                
                for i in 0..<coveredSegments {
                    let angle = Double(i) * 2 * .pi / Double(segments)
                    let nextAngle = Double(i + 1) * 2 * .pi / Double(segments)
                    
                    path.move(to: center)
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .init(radians: angle),
                        endAngle: .init(radians: nextAngle),
                        clockwise: false
                    )
                }
            }
            .stroke(coverageColor, lineWidth: 2)
        }
    }
    
    private var coverageColor: Color {
        switch coverage {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .yellow
        default:
            return .green
        }
    }
}

private struct QualityIndicator: View {
    let quality: Float
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 40, height: 40)
            
            Circle()
                .trim(from: 0, to: CGFloat(quality))
                .stroke(qualityColor, lineWidth: 2)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(quality * 100))%")
                .font(.caption2)
                .foregroundColor(.white)
        }
        .scaleEffect(isAnimating ? 1.1 : 1.0)
        .animation(
            .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = quality < 0.7
        }
    }
    
    private var qualityColor: Color {
        switch quality {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .yellow
        default:
            return .green
        }
    }
}