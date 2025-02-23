import SwiftUI
import Combine

public final class AnimationManager {
    public static let shared = AnimationManager()
    
    // Global animation durations
    public struct Duration {
        public static let veryShort: CGFloat = 0.15
        public static let short: CGFloat = 0.25
        public static let medium: CGFloat = 0.35
        public static let long: CGFloat = 0.5
        public static let veryLong: CGFloat = 0.75
    }
    
    // Spring configurations
    public struct Spring {
        public static let standard = Animation.spring(response: 0.3, dampingFraction: 0.7)
        public static let tight = Animation.spring(response: 0.25, dampingFraction: 0.9)
        public static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    }
    
    // Common transitions
    public enum TransitionType {
        case fade
        case slide
        case scale
        case custom(AnyTransition)
        
        var transition: AnyTransition {
            switch self {
            case .fade:
                return .opacity.combined(with: .scale(scale: 0.95))
            case .slide:
                return .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            case .scale:
                return .scale.combined(with: .opacity)
            case .custom(let transition):
                return transition
            }
        }
    }
    
    // Animation presets for common UI interactions
    public struct Preset {
        public static let buttonPress = Animation.spring(response: 0.3, dampingFraction: 0.6)
        public static let listItem = Animation.spring(response: 0.4, dampingFraction: 0.8)
        public static let modalPresentation = Animation.spring(response: 0.5, dampingFraction: 0.8)
        public static let cardExpansion = Animation.spring(response: 0.45, dampingFraction: 0.7)
    }
    
    // Gesture animation states
    public enum GestureState {
        case inactive
        case pressing
        case dragging(translation: CGSize)
        case releasing
        
        var scale: CGFloat {
            switch self {
            case .inactive:
                return 1.0
            case .pressing:
                return 0.95
            case .dragging:
                return 0.95
            case .releasing:
                return 1.0
            }
        }
        
        var opacity: CGFloat {
            switch self {
            case .inactive:
                return 1.0
            case .pressing:
                return 0.8
            case .dragging:
                return 0.8
            case .releasing:
                return 1.0
            }
        }
    }
    
    // ViewModifier for animated gestures
    public struct AnimatedPressGesture: ViewModifier {
        @GestureState private var gestureState = GestureState.inactive
        let action: () -> Void
        
        public func body(content: Content) -> some View {
            content
                .scaleEffect(gestureState.scale)
                .opacity(gestureState.opacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: gestureState)
                .gesture(
                    LongPressGesture(minimumDuration: 0)
                        .updating($gestureState) { currentState, gestureState, _ in
                            gestureState = .pressing
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                action()
                            }
                        }
                )
        }
    }
    
    // ViewModifier for animated list items
    public struct AnimatedListItem: ViewModifier {
        let delay: Double
        @State private var isVisible = false
        
        public func body(content: Content) -> some View {
            content
                .offset(y: isVisible ? 0 : 20)
                .opacity(isVisible ? 1 : 0)
                .onAppear {
                    withAnimation(
                        .spring(response: 0.4, dampingFraction: 0.8)
                        .delay(delay)
                    ) {
                        isVisible = true
                    }
                }
        }
    }
    
    // Helper functions for common animations
    public static func animate(
        withDuration duration: CGFloat = Duration.medium,
        delay: CGFloat = 0,
        animation: Animation? = .easeInOut,
        completion: (() -> Void)? = nil,
        animations: @escaping () -> Void
    ) {
        withAnimation(animation?.delay(delay)) {
            animations()
        }
        
        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + delay) {
                completion()
            }
        }
    }
    
    // Convenience modifiers
    public static func pressAction() -> AnimatedPressGesture {
        AnimatedPressGesture(action: {})
    }
    
    public static func listItem(delay: Double = 0) -> AnimatedListItem {
        AnimatedListItem(delay: delay)
    }
}

// Convenience View extensions
extension View {
    public func animatedPress(action: @escaping () -> Void = {}) -> some View {
        modifier(AnimationManager.AnimatedPressGesture(action: action))
    }
    
    public func animatedListItem(delay: Double = 0) -> some View {
        modifier(AnimationManager.AnimatedListItem(delay: delay))
    }
    
    public func transition(_ type: AnimationManager.TransitionType) -> some View {
        transition(type.transition)
    }
}