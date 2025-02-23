import SwiftUI
import Combine

public final class NavigationCoordinator: ObservableObject {
    public static let shared = NavigationCoordinator()
    
    @Published public var activeSheet: Sheet?
    @Published public var activeAlert: Alert?
    @Published public var navigationPath = NavigationPath()
    @Published public var gestureInProgress = false
    
    private var subscriptions = Set<AnyCancellable>()
    
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