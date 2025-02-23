import SwiftUI
import Combine

public final class LoadingAnimationManager: ObservableObject {
    public static let shared = LoadingAnimationManager()
    
    @Published public var isLoading = false
    @Published public var loadingStyle: LoadingStyle = .default
    @Published public var loadingProgress: Double = 0
    @Published public var loadingMessage: String?
    
    public enum LoadingStyle {
        case `default`
        case progress
        case indeterminate
        case success
        case error
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
            case .custom(let animation):
                return animation
            }
        }
    }
    
    public func startLoading(style: LoadingStyle = .default, message: String? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isLoading = true
            loadingStyle = style
            loadingMessage = message
            loadingProgress = 0
        }
    }
    
    public func updateProgress(_ progress: Double, message: String? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            loadingProgress = progress
            if let message = message {
                loadingMessage = message
            }
        }
    }
    
    public func stopLoading(completion: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isLoading = false
            loadingProgress = 0
            loadingMessage = nil
        }
        completion?()
    }
}

// Loading overlay view
public struct LoadingOverlay: View {
    @ObservedObject private var manager = LoadingAnimationManager.shared
    @State private var rotation: Double = 0
    
    public var body: some View {
        Group {
            if manager.isLoading {
                ZStack {
                    // Blur background
                    BlurView(style: .systemMaterial)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        switch manager.loadingStyle {
                        case .default:
                            defaultLoadingView
                        case .progress:
                            progressLoadingView
                        case .indeterminate:
                            indeterminateLoadingView
                        case .success:
                            successLoadingView
                        case .error:
                            errorLoadingView
                        case .custom:
                            customLoadingView
                        }
                        
                        if let message = manager.loadingMessage {
                            Text(message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }
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
    
    private var defaultLoadingView: some View {
        CircularLoadingView(color: Color(.systemBlue))
            .frame(width: 50, height: 50)
    }
    
    private var progressLoadingView: some View {
        CircularProgressView(progress: manager.loadingProgress)
            .frame(width: 50, height: 50)
    }
    
    private var indeterminateLoadingView: some View {
        IndeterminateLoadingView()
            .frame(width: 50, height: 50)
    }
    
    private var successLoadingView: some View {
        SuccessCheckmark()
            .frame(width: 50, height: 50)
    }
    
    private var errorLoadingView: some View {
        ErrorIcon()
            .frame(width: 50, height: 50)
    }
    
    private var customLoadingView: some View {
        PulsingLoadingView()
            .frame(width: 50, height: 50)
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