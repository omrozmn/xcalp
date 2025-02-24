import ARKit
import SceneKit
import simd
import SwiftUI

public final class MeshManipulationManager: ObservableObject {
    public static let shared = MeshManipulationManager()
    
    @Published public var rotationAngle: simd_float3 = .zero
    @Published public var translation: simd_float3 = .zero
    @Published public var scale: Float = 1.0
    @Published public var selectionMode: SelectionMode = .none
    @Published public var selectedPoints: Set<Int> = []
    
    public enum SelectionMode {
        case none
        case point
        case region
        case brush(radius: Float)
    }
    
    public struct ManipulationConstraints {
        var minScale: Float = 0.5
        var maxScale: Float = 2.0
        var rotationLimits: simd_float3 = simd_float3(Float.pi, Float.pi, Float.pi)
        var translationLimits: simd_float3 = simd_float3(100, 100, 100)
        var enableSelection: Bool = true
    }
    
    private var constraints = ManipulationConstraints()
    private var initialTouchPoints: [CGPoint] = []
    private var lastRotation: simd_float3 = .zero
    private var lastTranslation: simd_float3 = .zero
    private var lastScale: Float = 1.0
    
    public func setConstraints(_ constraints: ManipulationConstraints) {
        self.constraints = constraints
    }
    
    public func handlePanGesture(_ gesture: UIPanGestureState, in view: UIView) {
        switch gesture.state {
        case .began:
            handleGestureBegan(gesture, in: view)
        case .changed:
            handleGestureChanged(gesture, in: view)
        case .ended, .cancelled:
            handleGestureEnded()
        default:
            break
        }
    }
    
    public func handlePinchGesture(_ gesture: UIPinchGestureState) {
        switch gesture.state {
        case .began:
            lastScale = scale
        case .changed:
            let newScale = lastScale * Float(gesture.scale)
            scale = min(max(newScale, constraints.minScale), constraints.maxScale)
            
            // Provide haptic feedback at scale limits
            if newScale <= constraints.minScale || newScale >= constraints.maxScale {
                HapticFeedbackManager.shared.playFeedback(.impact(.medium))
            }
        case .ended:
            lastScale = scale
        default:
            break
        }
    }
    
    public func handleRotationGesture(_ gesture: UIRotationGestureState) {
        switch gesture.state {
        case .began:
            lastRotation = rotationAngle
        case .changed:
            let rotation = Float(gesture.rotation)
            rotationAngle = simd_float3(
                lastRotation.x,
                lastRotation.y + rotation,
                lastRotation.z
            )
            
            // Clamp rotation within limits
            rotationAngle = simd_clamp(
                rotationAngle,
                -constraints.rotationLimits,
                constraints.rotationLimits
            )
        case .ended:
            lastRotation = rotationAngle
        default:
            break
        }
    }
    
    public func handleSelection(_ point: CGPoint, in view: UIView, meshNode: SCNNode) {
        guard constraints.enableSelection else { return }
        
        switch selectionMode {
        case .point:
            handlePointSelection(point, in: view, meshNode: meshNode)
        case .region:
            handleRegionSelection(point, in: view, meshNode: meshNode)
        case .brush(let radius):
            handleBrushSelection(point, radius: radius, in: view, meshNode: meshNode)
        case .none:
            break
        }
    }
    
    private func handleGestureBegan(_ gesture: UIPanGestureState, in view: UIView) {
        initialTouchPoints = gesture.touches.map { $0.location(in: view) }
        lastTranslation = translation
    }
    
    private func handleGestureChanged(_ gesture: UIPanGestureState, in view: UIView) {
        guard let initialPoint = initialTouchPoints.first else { return }
        let translation = gesture.translation(in: view)
        let currentPoint = gesture.location(in: view)
        
        // Calculate 3D translation based on touch movement
        let translationDelta = calculateTranslationDelta(
            from: initialPoint,
            to: currentPoint,
            translation: translation,
            in: view
        )
        
        // Apply translation with constraints
        self.translation = simd_clamp(
            lastTranslation + translationDelta,
            -constraints.translationLimits,
            constraints.translationLimits
        )
    }
    
    private func handleGestureEnded() {
        lastTranslation = translation
        initialTouchPoints.removeAll()
    }
    
    private func calculateTranslationDelta(
        from start: CGPoint,
        to end: CGPoint,
        translation: CGPoint,
        in view: UIView
    ) -> simd_float3 {
        let viewSize = view.bounds.size
        let deltaX = Float(translation.x / viewSize.width)
        let deltaY = Float(translation.y / viewSize.height)
        
        return simd_float3(
            deltaX * constraints.translationLimits.x,
            -deltaY * constraints.translationLimits.y,
            0
        )
    }
    
    private func handlePointSelection(_ point: CGPoint, in view: UIView, meshNode: SCNNode) {
        guard let result = performHitTest(point, in: view, meshNode: meshNode) else { return }
        
        let vertexIndex = result.vertexIndex
        if selectedPoints.contains(vertexIndex) {
            selectedPoints.remove(vertexIndex)
        } else {
            selectedPoints.insert(vertexIndex)
            HapticFeedbackManager.shared.playFeedback(.selection)
        }
    }
    
    private func handleRegionSelection(_ point: CGPoint, in view: UIView, meshNode: SCNNode) {
        guard let result = performHitTest(point, in: view, meshNode: meshNode) else { return }
        
        let region = findConnectedRegion(startingFrom: result.vertexIndex, in: meshNode)
        selectedPoints.formUnion(region)
        
        if !region.isEmpty {
            HapticFeedbackManager.shared.playPattern(HapticFeedbackManager.successPattern)
        }
    }
    
    private func handleBrushSelection(_ point: CGPoint, radius: Float, in view: UIView, meshNode: SCNNode) {
        guard let hitResult = performHitTest(point, in: view, meshNode: meshNode) else { return }
        
        let vertices = getVerticesWithinRadius(
            center: hitResult.worldCoordinates,
            radius: radius,
            meshNode: meshNode
        )
        
        if !vertices.isEmpty {
            selectedPoints.formUnion(vertices)
            HapticFeedbackManager.shared.playFeedback(.impact(.light))
        }
    }
    
    private func performHitTest(_ point: CGPoint, in view: UIView, meshNode: SCNNode) -> SCNHitTestResult? {
        let hitResults = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .categoryBitMask: 1 << 0
        ])
        return hitResults.first
    }
    
    private func findConnectedRegion(startingFrom vertexIndex: Int, in meshNode: SCNNode) -> Set<Int> {
        var region: Set<Int> = []
        var queue: [Int] = [vertexIndex]
        
        while !queue.isEmpty {
            let currentIndex = queue.removeFirst()
            guard !region.contains(currentIndex) else { continue }
            
            region.insert(currentIndex)
            
            // Add neighboring vertices to queue
            let neighbors = getNeighboringVertices(for: currentIndex, in: meshNode)
            queue.append(contentsOf: neighbors.filter { !region.contains($0) })
        }
        
        return region
    }
    
    private func getVerticesWithinRadius(
        center: SCNVector3,
        radius: Float,
        meshNode: SCNNode
    ) -> Set<Int> {
        var vertices: Set<Int> = []
        let radiusSquared = radius * radius
        
        // TODO: Implement spatial indexing for better performance
        // Currently using simple distance check
        guard let geometry = meshNode.geometry as? SCNGeometry,
              let vertexSource = geometry.sources(for: .vertex).first else {
            return vertices
        }
        
        for i in 0..<vertexSource.data.count / MemoryLayout<SCNVector3>.size {
            var vertex = SCNVector3()
            vertexSource.data.withUnsafeBytes { buffer in
                vertex = buffer.load(fromByteOffset: i * MemoryLayout<SCNVector3>.size, as: SCNVector3.self)
            }
            
            let worldVertex = meshNode.convertPosition(vertex, to: nil)
            let distance = simd_distance_squared(
                simd_float3(worldVertex),
                simd_float3(center)
            )
            
            if distance <= radiusSquared {
                vertices.insert(i)
            }
        }
        
        return vertices
    }
    
    private func getNeighboringVertices(for vertexIndex: Int, in meshNode: SCNNode) -> [Int] {
        // TODO: Implement proper vertex connectivity
        // Currently returning empty array as placeholder
        []
    }
}

// Helper types for gesture handling
public struct UIPanGestureState {
    let state: UIGestureRecognizer.State
    let touches: Set<UITouch>
    let location: CGPoint
    let translation: CGPoint
    
    func translation(in view: UIView) -> CGPoint {
        translation
    }
    
    func location(in view: UIView) -> CGPoint {
        location
    }
}

public struct UIPinchGestureState {
    let state: UIGestureRecognizer.State
    let scale: CGFloat
}

public struct UIRotationGestureState {
    let state: UIGestureRecognizer.State
    let rotation: CGFloat
}

// View modifier for mesh manipulation
public struct MeshManipulationModifier: ViewModifier {
    @ObservedObject private var manager: MeshManipulationManager
    let meshNode: SCNNode
    
    public init(manager: MeshManipulationManager = .shared, meshNode: SCNNode) {
        self.manager = manager
        self.meshNode = meshNode
    }
    
    public func body(content: Content) -> some View {
        content
            .gesture(
                SimultaneousGesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                let state = UIPanGestureState(
                                    state: .changed,
                                    touches: [],
                                    location: value.location,
                                    translation: CGPoint(
                                        x: value.translation.width,
                                        y: value.translation.height
                                    )
                                )
                                manager.handlePanGesture(state, in: UIView())
                            },
                        MagnificationGesture()
                            .onChanged { value in
                                let state = UIPinchGestureState(
                                    state: .changed,
                                    scale: value
                                )
                                manager.handlePinchGesture(state)
                            }
                    ),
                    RotationGesture()
                        .onChanged { value in
                            let state = UIRotationGestureState(
                                state: .changed,
                                rotation: value.radians
                            )
                            manager.handleRotationGesture(state)
                        }
                )
            )
            .onChange(of: manager.selectionMode) { _ in
                // Handle selection mode changes
            }
    }
}

// View extension for mesh manipulation
extension View {
    public func meshManipulation(
        manager: MeshManipulationManager = .shared,
        meshNode: SCNNode
    ) -> some View {
        modifier(MeshManipulationModifier(manager: manager, meshNode: meshNode))
    }
}
