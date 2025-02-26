import SwiftUI

struct AnimatedTransitionView<Content: View>: View {
    let content: Content
    let state: ScanningState
    @State private var animationScale: CGFloat = 1.0
    @State private var animationOpacity: Double = 1.0
    
    init(state: ScanningState, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.state = state
    }
    
    var body: some View {
        content
            .scaleEffect(animationScale)
            .opacity(animationOpacity)
            .onChange(of: state) { newState in
                withAnimation(.spring()) {
                    switch newState {
                    case .scanning:
                        animationScale = 1.0
                        animationOpacity = 1.0
                    case .paused:
                        animationScale = 0.95
                        animationOpacity = 0.7
                    case .optimizing:
                        animationScale = 1.05
                        animationOpacity = 0.9
                    case .error:
                        animationScale = 0.9
                        animationOpacity = 0.5
                    case .idle:
                        animationScale = 1.0
                        animationOpacity = 0.3
                    }
                }
            }
    }
}

enum TransitionType {
    case slide
    case fade
    case scale
    case combined
}

struct SlidingTransition: ViewModifier {
    let isActive: Bool
    let edge: Edge
    
    func body(content: Content) -> some View {
        content
            .offset(
                x: offsetX,
                y: offsetY
            )
            .animation(.spring(), value: isActive)
    }
    
    private var offsetX: CGFloat {
        guard isActive else { return 0 }
        switch edge {
        case .leading: return -30
        case .trailing: return 30
        default: return 0
        }
    }
    
    private var offsetY: CGFloat {
        guard isActive else { return 0 }
        switch edge {
        case .top: return -30
        case .bottom: return 30
        default: return 0
        }
    }
}

struct FadingTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut, value: isActive)
    }
}

extension View {
    func transitionEffect(
        _ type: TransitionType,
        isActive: Bool,
        edge: Edge = .leading
    ) -> some View {
        switch type {
        case .slide:
            return AnyView(modifier(SlidingTransition(isActive: isActive, edge: edge)))
        case .fade:
            return AnyView(modifier(FadingTransition(isActive: isActive)))
        case .scale:
            return AnyView(scaleEffect(isActive ? 1 : 0.8)
                .animation(.spring(), value: isActive))
        case .combined:
            return AnyView(modifier(SlidingTransition(isActive: isActive, edge: edge))
                .modifier(FadingTransition(isActive: isActive))
                .scaleEffect(isActive ? 1 : 0.9))
        }
    }
}

struct FloatingTransition: ViewModifier {
    @State private var offsetY: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    offsetY = -5
                }
            }
    }
}