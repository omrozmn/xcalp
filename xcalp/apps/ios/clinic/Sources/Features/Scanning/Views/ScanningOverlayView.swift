import SwiftUI

struct ScanningOverlayView: View {
    let scanningQuality: Float
    let coverage: Float
    let hints: [OptimizationHint]
    let guideMessage: String
    let metrics: ScanningMetrics?
    let showingGuide: Bool
    let currentSpeed: Float
    let optimalSpeed: Float
    let speedGuidance: String
    
    @Environment(\.accessibilityEnabled) var accessibilityEnabled
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    
    var body: some View {
        ZStack {
            // Main scanning guide
            if showingGuide {
                ScanningGuideView(
                    scanningQuality: scanningQuality,
                    coverage: coverage,
                    hints: hints,
                    guideMessage: guideMessage
                )
            }
            
            VStack {
                // Top section - Optimization hints and metrics
                VStack(spacing: 16) {
                    if !hints.isEmpty {
                        OptimizationHintsView(hints: hints)
                            .transition(.move(edge: .top))
                    }
                    
                    if let metrics = metrics {
                        PerformanceMetricsView(metrics: metrics)
                            .transition(.move(edge: .top))
                    }
                }
                .padding(.top, 44)
                .padding(.horizontal)
                
                Spacer()
                
                // Speed gauge overlay
                SpeedGaugeView(
                    currentSpeed: currentSpeed,
                    optimalSpeed: optimalSpeed,
                    guidance: speedGuidance
                )
                .offset(y: -50)
                
                // Bottom section - Coverage and quality indicators
                VStack(spacing: 16) {
                    if showingGuide {
                        CoverageHeatmapView(
                            heatmap: [], // Will be populated by the feature
                            coverage: coverage
                        )
                        .frame(height: 100)
                        .transition(.move(edge: .bottom))
                    }
                    
                    ScanQualityMetricsView(
                        quality: scanningQuality,
                        pointCount: 0, // Will be populated by the feature
                        coverage: coverage,
                        blurAmount: 0, // Will be populated by the feature
                        isCompensatingBlur: false // Will be populated by the feature
                    )
                    .padding(.bottom, 44)
                }
                .padding(.horizontal)
            }
        }
        .animation(.spring(), value: showingGuide)
        .animation(.spring(), value: hints)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }
    
    private var accessibilityDescription: String {
        var description = "Scanning status: "
        
        description += "Quality is \(qualityDescription). "
        description += "Coverage is \(Int(coverage * 100)) percent. "
        description += "Speed is \(speedDescription). "
        
        if let highPriorityHint = hints.first(where: { $0.priority >= 4 }) {
            description += highPriorityHint.description
        }
        
        return description
    }
    
    private var qualityDescription: String {
        if scanningQuality < 0.3 {
            return "poor"
        } else if scanningQuality < 0.7 {
            return "fair"
        } else {
            return "good"
        }
    }
    
    private var speedDescription: String {
        if currentSpeed > optimalSpeed * 1.2 {
            return "too fast"
        } else if currentSpeed < optimalSpeed * 0.8 {
            return "too slow"
        } else {
            return "optimal"
        }
    }
}

// High contrast adaptive components
private struct AdaptiveStrokeStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) var contrast
    
    let color: Color
    let lineWidth: CGFloat
    
    func body(content: Content) -> some View {
        content.overlay(
            content
                .stroke(
                    color,
                    lineWidth: contrast == .increased ? lineWidth * 1.5 : lineWidth
                )
        )
    }
}

// Custom button style for consistent accessibility
struct AccessibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Preview provider for development
#if DEBUG
struct ScanningOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ScanningOverlayView(
            scanningQuality: 0.7,
            coverage: 0.65,
            hints: [
                OptimizationHint(
                    title: "Improve Scanning Pattern",
                    description: "Move the device in a more systematic pattern",
                    priority: 4,
                    actionRequired: true
                )
            ],
            guideMessage: "Continue scanning to fill gaps",
            metrics: nil,
            showingGuide: true,
            currentSpeed: 1.0,
            optimalSpeed: 1.0,
            speedGuidance: "Maintain a steady speed"
        )
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}