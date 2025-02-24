import Combine
import SwiftUI

public final class TreatmentTransitionCoordinator: ObservableObject {
    public static let shared = TreatmentTransitionCoordinator()
    
    @Published public var currentStage: TreatmentStage = .initial
    @Published public var isTransitioning = false
    private var subscriptions = Set<AnyCancellable>()
    
    public enum TreatmentStage {
        case initial
        case scanning
        case analysis
        case planning
        case review
        
        var animation: Animation {
            switch self {
            case .initial:
                return .easeInOut(duration: 0.4)
            case .scanning:
                return .spring(response: 0.5, dampingFraction: 0.8)
            case .analysis:
                return .spring(response: 0.6, dampingFraction: 0.85)
            case .planning:
                return .interpolatingSpring(mass: 1.0, stiffness: 100, damping: 15)
            case .review:
                return .spring(response: 0.5, dampingFraction: 0.75)
            }
        }
        
        var transition: AnyTransition {
            switch self {
            case .initial:
                return .opacity.combined(with: .scale(scale: 0.95))
            case .scanning:
                return .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                )
            case .analysis:
                return .asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            case .planning:
                return .modifier(
                    active: FlipTransitionModifier(angle: 180),
                    identity: FlipTransitionModifier(angle: 0)
                )
            case .review:
                return .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
    }
    
    public func transition(to stage: TreatmentStage, completion: (() -> Void)? = nil) {
        // Play appropriate haptic pattern for each stage transition
        switch stage {
        case .scanning:
            HapticFeedbackManager.shared.playPatternFeedback(HapticFeedbackManager.scanProgressPattern)
        case .analysis:
            HapticFeedbackManager.shared.playPatternFeedback(HapticFeedbackManager.measurementCompletePattern)
        case .planning:
            HapticFeedbackManager.shared.playPatternFeedback(HapticFeedbackManager.templateSelectionPattern)
        case .review:
            HapticFeedbackManager.shared.playPatternFeedback(HapticFeedbackManager.successPattern)
        default:
            break
        }
        
        withAnimation(stage.animation) {
            isTransitioning = true
            currentStage = stage
        }
        
        // Auto-reset transitioning state
        DispatchQueue.main.asyncAfter(deadline: .now() + stage.animation.duration) {
            withAnimation(stage.animation) {
                self.isTransitioning = false
                completion?()
            }
        }
    }
}

// Custom transition modifier for 3D treatment visualization
struct FlipTransitionModifier: ViewModifier {
    let angle: Double
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0.0, y: 1.0, z: 0.0)
            )
    }
}

// Treatment stage transition container
public struct TreatmentStageContainer<Content: View>: View {
    @ObservedObject private var coordinator = TreatmentTransitionCoordinator.shared
    let content: () -> Content
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        content()
            .transition(coordinator.currentStage.transition)
    }
}

// View extension for treatment transitions
extension View {
    public func withTreatmentTransition() -> some View {
        TreatmentStageContainer {
            self
        }
    }
}
