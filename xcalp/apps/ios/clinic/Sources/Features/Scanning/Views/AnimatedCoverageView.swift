import SwiftUI

struct AnimatedCoverageView: View {
    let coverage: Float
    let regions: [CoverageRegion]
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background grid
            CoverageGrid()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            
            // Coverage regions
            ForEach(regions) { region in
                CoverageRegion(
                    points: region.points,
                    opacity: region.density
                )
                .fill(coverageColor.opacity(Double(region.density)))
                .animation(.easeInOut(duration: 0.5), value: region.density)
            }
            
            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(coverage))
                .stroke(
                    coverageColor,
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            // Coverage percentage
            VStack {
                Text("\(Int(coverage * 100))%")
                    .font(.system(.title2, design: .rounded))
                    .bold()
                Text("Coverage")
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    private var coverageColor: Color {
        switch coverage {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .orange
        default:
            return .green
        }
    }
}

struct CoverageGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gridSize: CGFloat = 20
        
        // Vertical lines
        for x in stride(from: 0, through: rect.width, by: gridSize) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Horizontal lines
        for y in stride(from: 0, through: rect.height, by: gridSize) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

struct CoverageRegion: Shape, Identifiable {
    let id = UUID()
    let points: [CGPoint]
    let density: Float
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
struct AnimatedCoverageView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            AnimatedCoverageView(
                coverage: 0.65,
                regions: [
                    CoverageRegion(
                        points: [
                            CGPoint(x: 50, y: 50),
                            CGPoint(x: 100, y: 50),
                            CGPoint(x: 100, y: 100),
                            CGPoint(x: 50, y: 100)
                        ],
                        density: 0.8
                    )
                ]
            )
        }
        .frame(width: 200, height: 200)
        .previewLayout(.sizeThatFits)
    }
}