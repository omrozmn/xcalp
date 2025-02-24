import Combine
import SwiftUI

public final class TransitionAnimationCoordinator: ObservableObject {
    public static let shared = TransitionAnimationCoordinator()
    
    @Published public var currentTransition: TransitionType = .none
    @Published public var isTransitioning = false
    private var subscriptions = Set<AnyCancellable>()
    
    public enum TransitionType {
        case none
        case scanToAnalysis
        case analysisToPlanning
        case planningToSimulation
        case simulationToReport
        case custom(AnyTransition)
        
        var animation: Animation {
            switch self {
            case .none:
                return .default
            case .scanToAnalysis:
                return .spring(response: 0.5, dampingFraction: 0.8)
            case .analysisToPlanning:
                return .spring(response: 0.6, dampingFraction: 0.85)
            case .planningToSimulation:
                return .spring(response: 0.7, dampingFraction: 0.9)
            case .simulationToReport:
                return .spring(response: 0.5, dampingFraction: 0.8)
            case .custom:
                return .spring(response: 0.5, dampingFraction: 0.85)
            }
        }
        
        var transition: AnyTransition {
            switch self {
            case .none:
                return .identity
            case .scanToAnalysis:
                return .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                )
            case .analysisToPlanning:
                return .asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            case .planningToSimulation:
                return .modifier(
                    active: FlipTransitionModifier(angle: 180),
                    identity: FlipTransitionModifier(angle: 0)
                )
            case .simulationToReport:
                return .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            case .custom(let transition):
                return transition
            }
        }
    }
    
    public func performTransition(_ type: TransitionType, completion: (() -> Void)? = nil) {
        withAnimation(type.animation) {
            isTransitioning = true
            currentTransition = type
        }
        
        // Trigger haptic feedback based on transition type
        switch type {
        case .scanToAnalysis, .analysisToPlanning:
            HapticFeedbackManager.shared.playFeedback(.impact(.medium))
        case .planningToSimulation:
            HapticFeedbackManager.shared.playPattern(HapticFeedbackManager.templateSelectionPattern)
        case .simulationToReport:
            HapticFeedbackManager.shared.playFeedback(.success)
        default:
            break
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + type.animation.duration) {
            withAnimation(type.animation) {
                self.isTransitioning = false
                completion?()
            }
        }
    }
}

// Custom transition modifier for 3D flip effect
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

// Transition container view
public struct TransitionContainerView<Content: View>: View {
    @ObservedObject private var coordinator = TransitionAnimationCoordinator.shared
    let content: () -> Content
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        content()
            .transition(coordinator.currentTransition.transition)
    }
}

// Stage transition view for treatment workflow
public struct StageTransitionView<Content: View>: View {
    let stage: TreatmentFeature.PlanningStage
    let content: () -> Content
    @ObservedObject private var coordinator = TransitionAnimationCoordinator.shared
    
    public init(
        stage: TreatmentFeature.PlanningStage,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.stage = stage
        self.content = content
    }
    
    public var body: some View {
        content()
            .transition(transitionForStage(stage))
            .animation(animationForStage(stage), value: stage)
    }
    
    private func transitionForStage(_ stage: TreatmentFeature.PlanningStage) -> AnyTransition {
        switch stage {
        case .scanning:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.1)),
                removal: .opacity.combined(with: .scale(scale: 0.9))
            )
        case .analysis:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .planning:
            return .asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            )
        case .simulation:
            return .modifier(
                active: FlipTransitionModifier(angle: 180),
                identity: FlipTransitionModifier(angle: 0)
            )
        }
    }
    
    private func animationForStage(_ stage: TreatmentFeature.PlanningStage) -> Animation {
        switch stage {
        case .scanning:
            return .spring(response: 0.4, dampingFraction: 0.8)
        case .analysis:
            return .spring(response: 0.5, dampingFraction: 0.85)
        case .planning:
            return .spring(response: 0.6, dampingFraction: 0.9)
        case .simulation:
            return .spring(response: 0.7, dampingFraction: 0.85)
        }
    }
}

// View extensions for transitions
extension View {
    public func withTransition(_ type: TransitionAnimationCoordinator.TransitionType) -> some View {
        TransitionContainerView {
            self
        }
    }
    
    public func withStageTransition(_ stage: TreatmentFeature.PlanningStage) -> some View {
        StageTransitionView(stage: stage) {
            self
        }
    }
}
