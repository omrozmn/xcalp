import Combine
import CoreGraphics
import SwiftUI

public final class GestureRecognizerManager: ObservableObject {
    public static let shared = GestureRecognizerManager()
    
    @Published public var scale: CGFloat = 1.0
    @Published public var rotation: Angle = .zero
    @Published public var offset: CGSize = .zero
    @Published public var lastScale: CGFloat = 1.0
    @Published public var lastRotation: Angle = .zero
    @Published public var lastOffset: CGSize = .zero
    
    // Gesture state tracking
    @Published public var isScaling = false
    @Published public var isRotating = false
    @Published public var isDragging = false
    
    // Gesture constraints
    public struct Constraints {
        var minScale: CGFloat = 0.5
        var maxScale: CGFloat = 3.0
        var rotationEnabled = true
        var dragEnabled = true
        var boundsRect: CGRect?
    }
    
    private var constraints = Constraints()
    private var subscriptions = Set<AnyCancellable>()
    
    public func setConstraints(_ constraints: Constraints) {
        self.constraints = constraints
    }
    
    public func reset() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            scale = 1.0
            rotation = .zero
            offset = .zero
            lastScale = 1.0
            lastRotation = .zero
            lastOffset = .zero
        }
    }
    
    // Combined gesture handlers
    public var transformGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        handleScaleChange(value)
                    }
                    .onEnded { _ in
                        handleScaleEnd()
                    },
                RotationGesture()
                    .onChanged { angle in
                        handleRotationChange(angle)
                    }
                    .onEnded { _ in
                        handleRotationEnd()
                    }
            ),
            DragGesture()
                .onChanged { value in
                    handleDragChange(value)
                }
                .onEnded { _ in
                    handleDragEnd()
                }
        )
    }
    
    private func handleScaleChange(_ value: CGFloat) {
        guard !isRotating else { return }
        isScaling = true
        
        let newScale = lastScale * value
        scale = min(max(newScale, constraints.minScale), constraints.maxScale)
        
        // Provide haptic feedback on scale boundaries
        if newScale <= constraints.minScale || newScale >= constraints.maxScale {
            HapticFeedbackManager.shared.playFeedback(.impact(.medium))
        }
    }
    
    private func handleScaleEnd() {
        lastScale = scale
        isScaling = false
    }
    
    private func handleRotationChange(_ angle: Angle) {
        guard constraints.rotationEnabled && !isScaling else { return }
        isRotating = true
        
        rotation = lastRotation + angle
    }
    
    private func handleRotationEnd() {
        lastRotation = rotation
        isRotating = false
    }
    
    private func handleDragChange(_ value: DragGesture.Value) {
        guard constraints.dragEnabled else { return }
        isDragging = true
        
        var newOffset = CGSize(
            width: lastOffset.width + value.translation.width,
            height: lastOffset.height + value.translation.height
        )
        
        // Constrain to bounds if set
        if let bounds = constraints.boundsRect {
            let maxOffsetX = bounds.width * (scale - 1) / 2
            let maxOffsetY = bounds.height * (scale - 1) / 2
            
            newOffset.width = max(min(newOffset.width, maxOffsetX), -maxOffsetX)
            newOffset.height = max(min(newOffset.height, maxOffsetY), -maxOffsetY)
            
            // Provide haptic feedback when reaching bounds
            if abs(newOffset.width) >= maxOffsetX || abs(newOffset.height) >= maxOffsetY {
                HapticFeedbackManager.shared.playFeedback(.impact(.light))
            }
        }
        
        offset = newOffset
    }
    
    private func handleDragEnd() {
        lastOffset = offset
        isDragging = false
    }
}

// Transform modifier for views
public struct TransformModifier: ViewModifier {
    @ObservedObject private var manager: GestureRecognizerManager
    
    public init(manager: GestureRecognizerManager = .shared) {
        self.manager = manager
    }
    
    public func body(content: Content) -> some View {
        content
            .scaleEffect(manager.scale)
            .rotationEffect(manager.rotation)
            .offset(manager.offset)
            .gesture(manager.transformGesture)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.scale)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.rotation)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.offset)
    }
}

// Region selection modifier for treatment planning
public struct RegionSelectionModifier: ViewModifier {
    @Binding var selectedRegion: TreatmentRegion?
    let regions: [TreatmentRegion]
    @GestureState private var isPressed = false
    @State private var draggedRegion: TreatmentRegion?
    
    public func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        handleRegionSelection(at: value.location)
                    }
                    .onEnded { _ in
                        if let region = draggedRegion {
                            HapticFeedbackManager.shared.playFeedback(.selection)
                            selectedRegion = region
                        }
                        draggedRegion = nil
                    }
            )
            .opacity(isPressed ? 0.7 : 1.0)
    }
    
    private func handleRegionSelection(at point: CGPoint) {
        for region in regions {
            if region.bounds.contains(point) {
                if draggedRegion != region {
                    HapticFeedbackManager.shared.playFeedback(.impact(.light))
                    draggedRegion = region
                }
                return
            }
        }
        draggedRegion = nil
    }
}

// Convenience extensions for views
extension View {
    public func transformable(
        manager: GestureRecognizerManager = .shared,
        constraints: GestureRecognizerManager.Constraints? = nil
    ) -> some View {
        if let constraints = constraints {
            manager.setConstraints(constraints)
        }
        return modifier(TransformModifier(manager: manager))
    }
    
    public func regionSelection(
        selectedRegion: Binding<TreatmentRegion?>,
        regions: [TreatmentRegion]
    ) -> some View {
        modifier(RegionSelectionModifier(selectedRegion: selectedRegion, regions: regions))
    }
}
