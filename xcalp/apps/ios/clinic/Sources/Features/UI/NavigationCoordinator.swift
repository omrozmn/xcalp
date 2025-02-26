import Combine
import SwiftUI

public final class NavigationCoordinator: ObservableObject {
    public static let shared = NavigationCoordinator()
    
    @Published public var activeSheet: Sheet?
    @Published public var activeAlert: Alert?
    @Published public var navigationPath = NavigationPath()
    @Published public var gestureInProgress = false
    @Published public var transitionState: TransitionState = .idle
    @Published public var navigationHistory: [NavigationHistoryItem] = []
    @Published public var gestureProgress: CGFloat = 0
    
    private var subscriptions = Set<AnyCancellable>()
    private let maxHistoryItems = 50
    private var stateRestorationEnabled = true
    private var savedStates: [String: Any] = [:]
    
    public enum Sheet: Identifiable {
        case scanPreview(ScanHistoryManager.ScanVersion)
        case templateEditor(TreatmentTemplate?)
        case reportPreview(ReportGenerator.Report)
        case settings
        
        public var id: String {
            switch self {
            case .scanPreview: return "scanPreview"
            case .templateEditor: return "templateEditor"
            case .reportPreview: return "reportPreview"
            case .settings: return "settings"
            }
        }
    }
    
    public enum Alert: Identifiable {
        case error(Error)
        case confirmation(title: String, message: String, action: () -> Void)
        case warning(title: String, message: String)
        
        public var id: String {
            switch self {
            case .error: return "error"
            case .confirmation: return "confirmation"
            case .warning: return "warning"
            }
        }
    }
    
    public enum Transition {
        case push
        case present
        case custom(AnyTransition)
        
        var animation: Animation {
            switch self {
            case .push:
                return .spring(response: 0.35, dampingFraction: 0.8)
            case .present:
                return .spring(response: 0.5, dampingFraction: 0.8)
            case .custom:
                return .spring(response: 0.4, dampingFraction: 0.85)
            }
        }
        
        var transition: AnyTransition {
            switch self {
            case .push:
                return .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                )
            case .present:
                return .asymmetric(
                    insertion: .move(edge: .bottom),
                    removal: .move(edge: .bottom)
                )
            case .custom(let transition):
                return transition
            }
        }
    }
    
    public struct NavigationHistoryItem: Identifiable {
        public let id = UUID()
        let destination: AnyHashable
        let timestamp: Date
        let state: [String: Any]
    }
    
    public enum TransitionState {
        case idle
        case transitioning(progress: Double, direction: TransitionDirection)
        case interactive(progress: Double, direction: TransitionDirection)
    }
    
    public enum TransitionDirection {
        case forward, backward
    }
    
    public struct TransitionTiming {
        var duration: TimeInterval
        var dampingFraction: Double
        var response: Double
        
        static let `default` = TransitionTiming(
            duration: 0.35,
            dampingFraction: 0.8,
            response: 0.35
        )
        
        static let slow = TransitionTiming(
            duration: 0.5,
            dampingFraction: 0.85,
            response: 0.4
        )
        
        static let fast = TransitionTiming(
            duration: 0.25,
            dampingFraction: 0.75,
            response: 0.3
        )
    }
    
    public func navigate<T: Hashable>(
        to destination: T,
        transition: Transition = .push,
        timing: TransitionTiming = .default,
        saveState: Bool = true
    ) {
        // Save current state before navigation
        if saveState {
            saveNavigationState()
        }
        
        withAnimation(.spring(
            response: timing.response,
            dampingFraction: timing.dampingFraction,
            blendDuration: timing.duration
        )) {
            transitionState = .transitioning(progress: 0, direction: .forward)
            navigationPath.append(destination)
            
            // Add to history
            addToHistory(destination)
        }
        
        // Complete transition
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.duration) {
            self.transitionState = .idle
        }
        
        // Trigger haptic feedback
        HapticFeedbackManager.shared.playFeedback(.selection)
    }
    
    public func navigateBack(
        timing: TransitionTiming = .default,
        saveState: Bool = true
    ) {
        guard !navigationPath.isEmpty else { return }
        
        // Save state before going back
        if saveState {
            saveNavigationState()
        }
        
        withAnimation(.spring(
            response: timing.response,
            dampingFraction: timing.dampingFraction,
            blendDuration: timing.duration
        )) {
            transitionState = .transitioning(progress: 0, direction: .backward)
            navigationPath.removeLast()
            
            // Remove last history item
            if !navigationHistory.isEmpty {
                navigationHistory.removeLast()
            }
        }
        
        // Complete transition
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.duration) {
            self.transitionState = .idle
            // Restore previous state
            self.restoreNavigationState()
        }
        
        // Trigger haptic feedback
        HapticFeedbackManager.shared.playFeedback(.impact(.light))
    }
    
    public func handleNavigationGesture(_ value: DragGesture.Value) {
        let progress = min(1, max(0, value.translation.width / UIScreen.main.bounds.width))
        
        switch value.phase {
        case .began:
            gestureInProgress = true
            
        case .changed:
            gestureProgress = progress
            transitionState = .interactive(progress: Double(progress), direction: .backward)
            
        case .ended:
            gestureInProgress = false
            if progress > 0.5 {
                navigateBack(timing: .fast)
            } else {
                // Cancel navigation
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    gestureProgress = 0
                    transitionState = .idle
                }
            }
            
        default:
            break
        }
    }
    
    private func addToHistory(_ destination: AnyHashable) {
        let historyItem = NavigationHistoryItem(
            destination: destination,
            timestamp: Date(),
            state: savedStates
        )
        
        navigationHistory.append(historyItem)
        
        // Maintain history size
        if navigationHistory.count > maxHistoryItems {
            navigationHistory.removeFirst()
        }
    }
    
    private func saveNavigationState() {
        guard stateRestorationEnabled else { return }
        
        // Save current view state
        savedStates = [:]
        NotificationCenter.default.post(
            name: .saveNavigationState,
            object: nil,
            userInfo: ["callback": { [weak self] (key: String, value: Any) in
                self?.savedStates[key] = value
            }]
        )
    }
    
    private func restoreNavigationState() {
        guard stateRestorationEnabled,
              let previousState = navigationHistory.last?.state else {
            return
        }
        
        NotificationCenter.default.post(
            name: .restoreNavigationState,
            object: nil,
            userInfo: ["state": previousState]
        )
    }
    
    public func navigate<T: Hashable>(to destination: T, transition: Transition = .push) {
        withAnimation(transition.animation) {
            navigationPath.append(destination)
        }
    }
    
    public func navigateBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            navigationPath.removeLast()
        }
    }
    
    public func navigateToRoot() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            navigationPath.removeLast(navigationPath.count)
        }
    }
    
    public func presentSheet(_ sheet: Sheet) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            activeSheet = sheet
        }
    }
    
    public func dismissSheet() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeSheet = nil
        }
    }
    
    public func showAlert(_ alert: Alert) {
        activeAlert = alert
    }
    
    public func dismissAlert() {
        activeAlert = nil
    }
}

// Navigation view modifier for custom transitions
public struct CustomNavigationTransition: ViewModifier {
    let transition: NavigationCoordinator.Transition
    
    public func body(content: Content) -> some View {
        content
            .transition(transition.transition)
            .animation(transition.animation, value: true)
    }
}

// Navigation view modifier for gesture-based navigation
public struct NavigationGestures: ViewModifier {
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    @GestureState private var translation: CGFloat = 0
    
    public func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .updating($translation) { value, state, _ in
                        state = value.translation.width
                    }
                    .onChanged { _ in
                        coordinator.gestureInProgress = true
                    }
                    .onEnded { value in
                        coordinator.gestureInProgress = false
                        if value.translation.width > 100 && value.translation.height < 50 {
                            coordinator.navigateBack()
                        }
                    }
            )
            .offset(x: max(0, translation))
    }
}

// Navigation view modifier for custom sheet presentations
public struct CustomSheetPresentation: ViewModifier {
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    let content: (NavigationCoordinator.Sheet) -> AnyView
    
    public func body(content: Content) -> some View {
        content
            .sheet(item: $coordinator.activeSheet) { sheet in
                self.content(sheet)
                    .transition(.move(edge: .bottom))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: coordinator.activeSheet)
            }
    }
}

// View extensions for navigation modifiers
extension View {
    public func customNavigationTransition(_ transition: NavigationCoordinator.Transition) -> some View {
        modifier(CustomNavigationTransition(transition: transition))
    }
    
    public func navigationGestures() -> some View {
        modifier(NavigationGestures())
    }
    
    public func customSheetPresentation(@ViewBuilder content: @escaping (NavigationCoordinator.Sheet) -> AnyView) -> some View {
        modifier(CustomSheetPresentation(content: content))
    }
    
    public func enhancedNavigationGestures() -> some View {
        modifier(EnhancedNavigationGestures())
    }
    
    public func saveNavigationState(_ key: String, value: Any) -> some View {
        onAppear {
            if let callback = NotificationCenter.default.notificationQueue(
                forName: .saveNavigationState
            )?.last?.userInfo?["callback"] as? (String, Any) -> Void {
                callback(key, value)
            }
        }
    }
}

// Helper for type-safe navigation destinations
public protocol NavigationDestination: Hashable {
    associatedtype Content: View
    @ViewBuilder var destination: Content { get }
}

// Extension for handling navigation destinations
extension NavigationCoordinator {
    public func navigate<D: NavigationDestination>(to destination: D, transition: Transition = .push) {
        navigate(to: AnyNavigationDestination(destination), transition: transition)
    }
}

// Type erasure for navigation destinations
public struct AnyNavigationDestination: Hashable {
    private let destination: AnyHashable
    private let content: AnyView
    
    public init<D: NavigationDestination>(_ destination: D) {
        self.destination = destination
        self.content = AnyView(destination.destination)
    }
    
    public static func == (lhs: AnyNavigationDestination, rhs: AnyNavigationDestination) -> Bool {
        lhs.destination == rhs.destination
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(destination)
    }
    
    @ViewBuilder
    public var destinationView: some View {
        content
    }
}

// Navigation state restoration
extension Notification.Name {
    static let saveNavigationState = Notification.Name("saveNavigationState")
    static let restoreNavigationState = Notification.Name("restoreNavigationState")
}

// Enhanced navigation gestures modifier
public struct EnhancedNavigationGestures: ViewModifier {
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    @GestureState private var translation: CGFloat = 0
    
    public func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .updating($translation) { value, state, _ in
                        state = value.translation.width
                    }
                    .onChanged { value in
                        coordinator.handleNavigationGesture(value)
                    }
            )
            .offset(x: coordinator.gestureProgress * 200)
            .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: coordinator.gestureProgress)
    }
}

// State restoration helper
public protocol StateRestorable {
    func saveState() -> Any
    func restoreState(_ state: Any)
}

// Transition animation helper
extension AnyTransition {
    public static func adaptive(
        edge: Edge,
        timing: NavigationCoordinator.TransitionTiming = .default
    ) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge)
                .combined(with: .opacity)
                .animation(.spring(
                    response: timing.response,
                    dampingFraction: timing.dampingFraction,
                    blendDuration: timing.duration
                )),
            removal: .move(edge: edge)
                .combined(with: .opacity)
                .animation(.spring(
                    response: timing.response,
                    dampingFraction: timing.dampingFraction,
                    blendDuration: timing.duration
                ))
        )
    }
}
