import Combine
import SwiftUI

public final class LoadingAnimationManager: ObservableObject {
    public static let shared = LoadingAnimationManager()
    
    @Published public var isLoading = false
    @Published public var loadingStyle: LoadingStyle = .default
    @Published public var loadingProgress: Double = 0
    @Published public var loadingMessage: String?
    @Published public var secondaryMessage: String?
    @Published public var isInterruptible = false
    @Published public var estimatedTimeRemaining: TimeInterval?
    @Published public var performanceMetrics: PerformanceMetrics?
    @Published public var adaptiveAnimation: Bool = true
    
    private var progressHistory: [(timestamp: TimeInterval, progress: Double)] = []
    private var thermalState: ProcessorThermalState = .nominal
    private let maxHistoryPoints = 50
    
    public struct PerformanceMetrics {
        var processingSpeed: Double  // items/second
        var memoryUsage: UInt64     // bytes
        var gpuUtilization: Float   // 0-1
        var progressRate: Double     // progress/second
    }
    
    public enum ProcessorThermalState {
        case nominal, fair, serious, critical
    }
    
    public enum LoadingStyle {
        case `default`
        case progress
        case indeterminate
        case success
        case error
        case scanning
        case processing
        case analyzing
        case custom(Animation)
        
        var animation: Animation {
            switch self {
            case .default:
                return .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
            case .progress:
                return .spring(response: 0.35, dampingFraction: 0.8)
            case .indeterminate:
                return .linear(duration: 1.5).repeatForever(autoreverses: false)
            case .success:
                return .spring(response: 0.4, dampingFraction: 0.7)
            case .error:
                return .spring(response: 0.3, dampingFraction: 0.5)
            case .scanning:
                return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            case .processing:
                return .easeInOut(duration: 1.2).repeatForever(autoreverses: false)
            case .analyzing:
                return .spring(response: 0.6, dampingFraction: 0.8)
            case .custom(let animation):
                return animation
            }
        }
    }
    
    public func startLoading(
        style: LoadingStyle = .default,
        message: String? = nil,
        secondaryMessage: String? = nil,
        isInterruptible: Bool = false,
        estimatedDuration: TimeInterval? = nil
    ) {
        progressHistory.removeAll()
        performanceMetrics = nil
        estimatedTimeRemaining = estimatedDuration
        
        // Record initial progress point
        progressHistory.append((CACurrentMediaTime(), 0))
        
        // Monitor thermal state
        monitorThermalState()
        
        withAnimation(getAdaptiveAnimation()) {
            self.isLoading = true
            self.loadingStyle = style
            self.loadingMessage = message
            self.secondaryMessage = secondaryMessage
            self.isInterruptible = isInterruptible
            self.loadingProgress = 0
        }
        
        playHapticFeedback(for: style)
    }
    
    public func updateProgress(
        _ progress: Double,
        message: String? = nil,
        secondaryMessage: String? = nil,
        currentMemoryUsage: UInt64? = nil,
        gpuUtilization: Float? = nil
    ) {
        let currentTime = CACurrentMediaTime()
        progressHistory.append((currentTime, progress))
        
        // Keep only recent history
        if progressHistory.count > maxHistoryPoints {
            progressHistory.removeFirst()
        }
        
        // Calculate performance metrics
        updatePerformanceMetrics(
            currentTime: currentTime,
            memoryUsage: currentMemoryUsage,
            gpuUtilization: gpuUtilization
        )
        
        // Update estimated time remaining
        updateTimeEstimate()
        
        // Adapt animation based on performance
        let animation = getAdaptiveAnimation()
        
        withAnimation(animation) {
            self.loadingProgress = progress
            if let message = message {
                self.loadingMessage = message
            }
            if let secondaryMessage = secondaryMessage {
                self.secondaryMessage = secondaryMessage
            }
        }
        
        // Provide adaptive haptic feedback
        provideProgressHapticFeedback(progress)
    }
    
    public func stopLoading(
        withSuccess: Bool = true,
        message: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if withSuccess {
                loadingStyle = .success
                HapticFeedbackManager.shared.playFeedback(.success)
            } else {
                loadingStyle = .error
                HapticFeedbackManager.shared.playFeedback(.error)
            }
            
            if let message = message {
                loadingMessage = message
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.isLoading = false
                self.loadingProgress = 0
                self.loadingMessage = nil
                self.secondaryMessage = nil
            }
            completion?()
        }
    }
    
    public func interrupt() {
        guard isInterruptible else { return }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isLoading = false
            loadingProgress = 0
            loadingMessage = nil
            secondaryMessage = nil
        }
        
        HapticFeedbackManager.shared.playFeedback(.impact(.medium))
    }
    
    private func updatePerformanceMetrics(
        currentTime: TimeInterval,
        memoryUsage: UInt64?,
        gpuUtilization: Float?
    ) {
        guard progressHistory.count >= 2 else { return }
        
        let recent = progressHistory.suffix(10)
        let timeSpan = recent.last!.timestamp - recent.first!.timestamp
        let progressSpan = recent.last!.progress - recent.first!.progress
        
        let progressRate = timeSpan > 0 ? progressSpan / timeSpan : 0
        
        performanceMetrics = PerformanceMetrics(
            processingSpeed: progressRate * 100, // Convert to percentage/second
            memoryUsage: memoryUsage ?? 0,
            gpuUtilization: gpuUtilization ?? 0,
            progressRate: progressRate
        )
    }
    
    private func updateTimeEstimate() {
        guard progressHistory.count >= 2,
              let currentProgress = progressHistory.last?.progress,
              currentProgress > 0 else {
            return
        }
        
        // Calculate average progress rate from recent history
        let recent = progressHistory.suffix(min(10, progressHistory.count))
        let timeSpan = recent.last!.timestamp - recent.first!.timestamp
        let progressSpan = recent.last!.progress - recent.first!.progress
        
        let progressRate = progressSpan / timeSpan
        
        if progressRate > 0 {
            let remainingProgress = 1.0 - currentProgress
            estimatedTimeRemaining = remainingProgress / progressRate
        }
    }
    
    private func getAdaptiveAnimation() -> Animation {
        guard adaptiveAnimation else {
            return loadingStyle.animation
        }
        
        // Adapt animation based on thermal state and performance
        let duration = getAdaptiveDuration()
        let dampingFraction = getAdaptiveDampingFraction()
        
        switch loadingStyle {
        case .progress:
            return .spring(response: duration, dampingFraction: dampingFraction)
        case .processing:
            return .easeInOut(duration: duration).repeatForever(autoreverses: false)
        default:
            return loadingStyle.animation
        }
    }
    
    private func getAdaptiveDuration() -> Double {
        switch thermalState {
        case .critical:
            return 1.2 // Slower animations
        case .serious:
            return 0.8
        case .fair:
            return 0.6
        case .nominal:
            return 0.4 // Faster animations
        }
    }
    
    private func getAdaptiveDampingFraction() -> Double {
        switch thermalState {
        case .critical:
            return 0.9 // More damping
        case .serious:
            return 0.8
        case .fair:
            return 0.7
        case .nominal:
            return 0.6 // Less damping
        }
    }
    
    private func monitorThermalState() {
        #if os(iOS)
        ProcessInfo.processInfo.thermalStateDidChangeNotification
            .publisher
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
        #endif
    }
    
    private func updateThermalState() {
        #if os(iOS)
        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            thermalState = .critical
        case .serious:
            thermalState = .serious
        case .fair:
            thermalState = .fair
        case .nominal:
            thermalState = .nominal
        @unknown default:
            thermalState = .nominal
        }
        #endif
    }
    
    private func provideProgressHapticFeedback(_ progress: Double) {
        // Provide haptic feedback at key progress points
        let feedbackThresholds: Set<Double> = [0.25, 0.5, 0.75, 1.0]
        
        // Find the nearest threshold that we just passed
        for threshold in feedbackThresholds {
            let previous = progressHistory.dropLast().last?.progress ?? 0
            if previous < threshold && progress >= threshold {
                // Adapt feedback intensity based on thermal state
                let intensity: UIImpactFeedbackGenerator.FeedbackStyle
                switch thermalState {
                case .critical:
                    intensity = .light
                case .serious, .fair:
                    intensity = .medium
                case .nominal:
                    intensity = .rigid
                }
                
                HapticFeedbackManager.shared.playFeedback(.impact(intensity))
                break
            }
        }
    }
    
    private func playHapticFeedback(for style: LoadingStyle) {
        // Skip haptic feedback in critical thermal state
        guard thermalState != .critical else { return }
        
        switch style {
        case .scanning:
            HapticFeedbackManager.shared.playFeedback(.impact(.light))
        case .processing:
            HapticFeedbackManager.shared.playFeedback(.impact(.medium))
        case .analyzing:
            HapticFeedbackManager.shared.playPattern(HapticFeedbackManager.analysisStartPattern)
        default:
            break
        }
    }
}

// Loading overlay view with enhanced animations
public struct LoadingOverlay: View {
    @ObservedObject private var manager = LoadingAnimationManager.shared
    
    public var body: some View {
        Group {
            if manager.isLoading {
                ZStack {
                    // Enhanced blur background
                    BlurView(style: .systemMaterial)
                        .ignoresSafeArea()
                        .opacity(0.9)
                    
                    VStack(spacing: 20) {
                        Group {
                            switch manager.loadingStyle {
                            case .default:
                                CircularLoadingView(color: .accentColor)
                            case .progress:
                                CircularProgressView(progress: manager.loadingProgress)
                            case .indeterminate:
                                IndeterminateLoadingView()
                            case .success:
                                SuccessCheckmark()
                            case .error:
                                ErrorIcon()
                            case .scanning:
                                ScanningLoadingView()
                            case .processing:
                                ProcessingLoadingView()
                            case .analyzing:
                                AnalyzingLoadingView()
                            case .custom:
                                CustomLoadingView()
                            }
                        }
                        .frame(width: 60, height: 60)
                        
                        VStack(spacing: 8) {
                            if let message = manager.loadingMessage {
                                Text(message)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            if let secondary = manager.secondaryMessage {
                                Text(secondary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            if case .progress = manager.loadingStyle {
                                Text("\(Int(manager.loadingProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        
                        if manager.isInterruptible {
                            Button("Cancel") {
                                manager.interrupt()
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                            .padding(.top)
                        }
                        
                        metricsView
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(radius: 20)
                    )
                    .padding(40)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(manager.loadingStyle.animation, value: manager.isLoading)
    }
    
    private var metricsView: some View {
        Group {
            if let metrics = LoadingAnimationManager.shared.performanceMetrics {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing Speed: \(String(format: "%.1f", metrics.processingSpeed))/s")
                        .font(.caption2)
                    Text("Memory Usage: \(ByteCountFormatter.string(fromByteCount: Int64(metrics.memoryUsage), countStyle: .memory))")
                        .font(.caption2)
                    if metrics.gpuUtilization > 0 {
                        Text("GPU Usage: \(String(format: "%.0f%%", metrics.gpuUtilization * 100))")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            
            if let timeRemaining = LoadingAnimationManager.shared.estimatedTimeRemaining {
                Text("Estimated time remaining: \(timeString(from: timeRemaining))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        if timeInterval < 60 {
            return String(format: "%.0f seconds", timeInterval)
        } else if timeInterval < 3600 {
            return String(format: "%.1f minutes", timeInterval / 60)
        } else {
            return String(format: "%.1f hours", timeInterval / 3600)
        }
    }
}

// Custom loading animation views
private struct CircularLoadingView: View {
    let color: Color
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

private struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(Angle(degrees: -90))
        }
    }
}

private struct IndeterminateLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<5) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * 0.15, height: geometry.size.width * 0.15)
                    .offset(y: geometry.size.height * 0.3)
                    .rotationEffect(Angle(degrees: Double(index) * 72))
                    .scaleEffect(isAnimating ? 0.3 : 1)
                    .opacity(isAnimating ? 0.3 : 1)
                    .animation(
                        Animation
                            .easeInOut(duration: 1)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

private struct SuccessCheckmark: View {
    @State private var isAnimating = false
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: 25))
            path.addLine(to: CGPoint(x: 20, y: 35))
            path.addLine(to: CGPoint(x: 40, y: 15))
        }
        .trim(from: 0, to: isAnimating ? 1 : 0)
        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .animation(.easeInOut(duration: 0.3), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

private struct ErrorIcon: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 15, y: 15))
                path.addLine(to: CGPoint(x: 35, y: 35))
            }
            .trim(from: 0, to: isAnimating ? 1 : 0)
            
            Path { path in
                path.move(to: CGPoint(x: 35, y: 15))
                path.addLine(to: CGPoint(x: 15, y: 35))
            }
            .trim(from: 0, to: isAnimating ? 1 : 0)
        }
        .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .animation(.easeInOut(duration: 0.3), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

private struct PulsingLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.blue.opacity(0.5))
                    .scaleEffect(isAnimating ? 2 : 1)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        Animation
                            .easeInOut(duration: 1.5)
                            .repeatForever()
                            .delay(Double(index) * 0.3),
                        value: isAnimating
                    )
            }
            Circle()
                .fill(Color.blue)
                .frame(width: 20, height: 20)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// New specialized loading animations
private struct ScanningLoadingView: View {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    
    var body: some View {
        ZStack {
            // Scanning frame
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                
            // Scanning line
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 40)
                .offset(y: -20)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                scale = 0.8
            }
        }
    }
}

private struct ProcessingLoadingView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let rings = 3
            let strokeWidth: CGFloat = 4
            
            for ring in 0..<rings {
                let scale = 1.0 - (CGFloat(ring) * 0.2)
                let opacity = 1.0 - (CGFloat(ring) * 0.3)
                let rotation = phase + (CGFloat(ring) * .pi / 4)
                
                context.opacity = opacity
                context.scaleBy(x: scale, y: scale)
                context.rotate(by: .radians(Double(rotation)))
                
                let rect = CGRect(x: strokeWidth / 2, y: strokeWidth / 2,
                                width: size.width - strokeWidth,
                                height: size.height - strokeWidth)
                
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.accentColor),
                    lineWidth: strokeWidth
                )
            }
        }
        .frame(width: 50, height: 50)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}

private struct AnalyzingLoadingView: View {
    @State private var progress: CGFloat = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(
                    lineWidth: 4,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))
            
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .offset(y: -20)
                    .rotationEffect(.degrees(Double(index) * 120 + Double(progress) * 360))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

// Helper blur view
private struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

// View extension for loading overlay
extension View {
    public func loadingOverlay() -> some View {
        ZStack {
            self
            LoadingOverlay()
        }
    }
}
