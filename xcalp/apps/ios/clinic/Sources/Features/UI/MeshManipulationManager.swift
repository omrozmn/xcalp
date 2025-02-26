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
    
    // Add spatial indexing for efficient vertex queries
    private var spatialIndex: SpatialIndex?
    private var transformationBuffer: TransformationBuffer
    private var selectionHistory: [Set<Int>] = []
    private let maxHistorySize = 20
    
    private struct SpatialIndex {
        var cells: [Int: Set<Int>] = [:]
        let cellSize: Float
        
        init(vertices: [simd_float3], cellSize: Float = 0.01) {
            self.cellSize = cellSize
            
            // Build spatial index
            for (index, vertex) in vertices.enumerated() {
                let cell = getCellKey(for: vertex)
                cells[cell, default: []].insert(index)
            }
        }
        
        func getCellKey(for position: simd_float3) -> Int {
            let x = Int(floor(position.x / cellSize))
            let y = Int(floor(position.y / cellSize))
            let z = Int(floor(position.z / cellSize))
            return x &+ (y &* 73856093) &+ (z &* 19349663)
        }
        
        func getVerticesInRadius(_ center: simd_float3, radius: Float) -> Set<Int> {
            let radiusInCells = Int(ceil(radius / cellSize))
            var result = Set<Int>()
            
            for x in -radiusInCells...radiusInCells {
                for y in -radiusInCells...radiusInCells {
                    for z in -radiusInCells...radiusInCells {
                        let cellCenter = simd_float3(
                            Float(x) * cellSize,
                            Float(y) * cellSize,
                            Float(z) * cellSize
                        )
                        let cellKey = getCellKey(for: center + cellCenter)
                        if let vertices = cells[cellKey] {
                            result.formUnion(vertices)
                        }
                    }
                }
            }
            
            return result
        }
    }
    
    private struct TransformationBuffer {
        var transformations: [simd_float4x4] = []
        var timestamps: [TimeInterval] = []
        let maxBufferSize = 60
        
        mutating func add(_ transform: simd_float4x4) {
            transformations.append(transform)
            timestamps.append(CACurrentMediaTime())
            
            if transformations.count > maxBufferSize {
                transformations.removeFirst()
                timestamps.removeFirst()
            }
        }
        
        func predictNextTransform() -> simd_float4x4? {
            guard transformations.count >= 2 else { return nil }
            
            // Calculate velocity from last two transforms
            let lastTransform = transformations.last!
            let previousTransform = transformations[transformations.count - 2]
            let timeDelta = timestamps.last! - timestamps[timestamps.count - 2]
            
            // Extract translation and rotation
            let lastTranslation = lastTransform.columns.3.xyz
            let prevTranslation = previousTransform.columns.3.xyz
            
            // Calculate velocity
            let velocity = (lastTranslation - prevTranslation) / Float(timeDelta)
            
            // Predict next position
            let predictedTranslation = lastTranslation + velocity * Float(1.0 / 60.0) // Assuming 60fps
            
            // Create predicted transform
            var predictedTransform = lastTransform
            predictedTransform.columns.3 = simd_float4(predictedTranslation, 1)
            
            return predictedTransform
        }
    }
    
    public func setConstraints(_ constraints: ManipulationConstraints) {
        self.constraints = constraints
    }
    
    public func handlePanGesture(_ gesture: UIPanGestureState, in view: UIView) {
        switch gesture.state {
        case .began:
            handleGestureBegan(gesture, in: view)
        case .changed:
            handleGestureChanged(gesture, in: view)
            
            // Update transformation buffer for prediction
            let transform = simd_float4x4(
                translation: translation,
                rotation: rotationAngle,
                scale: scale
            )
            transformationBuffer.add(transform)
            
        case .ended, .cancelled:
            handleGestureEnded()
            
            // Apply inertia using predicted transform
            if let predictedTransform = transformationBuffer.predictNextTransform() {
                applyInertia(with: predictedTransform)
            }
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
        var region = Set<Int>()
        var queue = CircularBuffer<Int>(capacity: 1000)
        queue.push(vertexIndex)
        
        while let currentIndex = queue.pop() {
            guard !region.contains(currentIndex) else { continue }
            
            region.insert(currentIndex)
            
            // Get neighboring vertices using spatial index
            if let spatialIndex = spatialIndex {
                let vertex = getVertexPosition(at: currentIndex, in: meshNode)
                let neighbors = spatialIndex.getVerticesInRadius(vertex, radius: 0.01)
                
                for neighbor in neighbors where !region.contains(neighbor) {
                    queue.push(neighbor)
                }
            }
        }
        
        return region
    }
    
    private func getVerticesWithinRadius(
        center: SCNVector3,
        radius: Float,
        meshNode: SCNNode
    ) -> Set<Int> {
        guard let spatialIndex = spatialIndex else {
            return Set<Int>()
        }
        
        let worldCenter = simd_float3(center)
        return spatialIndex.getVerticesInRadius(worldCenter, radius: radius)
    }
    
    private func getVertexPosition(at index: Int, in meshNode: SCNNode) -> simd_float3 {
        guard let geometry = meshNode.geometry as? SCNGeometry,
              let vertexSource = geometry.sources(for: .vertex).first else {
            return .zero
        }
        
        var vertex = SCNVector3()
        vertexSource.data.withUnsafeBytes { buffer in
            vertex = buffer.load(fromByteOffset: index * MemoryLayout<SCNVector3>.size, as: SCNVector3.self)
        }
        
        let worldVertex = meshNode.convertPosition(vertex, to: nil)
        return simd_float3(worldVertex)
    }
    
    public func updateSpatialIndex(with vertices: [simd_float3]) {
        spatialIndex = SpatialIndex(vertices: vertices)
    }
    
    public func undo() {
        guard !selectionHistory.isEmpty else { return }
        selectedPoints = selectionHistory.removeLast()
        HapticFeedbackManager.shared.playFeedback(.selection)
    }
    
    private func saveSelectionState() {
        selectionHistory.append(selectedPoints)
        if selectionHistory.count > maxHistorySize {
            selectionHistory.removeFirst()
        }
    }
    
    private func getNeighboringVertices(for vertexIndex: Int, in meshNode: SCNNode) -> [Int] {
        // TODO: Implement proper vertex connectivity
        // Currently returning empty array as placeholder
        []
    }
    
    private func applyInertia(with predictedTransform: simd_float4x4) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            translation = predictedTransform.columns.3.xyz
            // Update rotation and scale if needed
        }
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

// Helper extension for simd operations
extension simd_float4x4 {
    init(translation: simd_float3, rotation: simd_float3, scale: Float) {
        let scaleMatrix = simd_float4x4(diagonal: simd_float4(scale, scale, scale, 1))
        let rotationMatrix = simd_float4x4(rotationYXZ: rotation)
        let translationMatrix = simd_float4x4(
            columns: (
                simd_float4(1, 0, 0, 0),
                simd_float4(0, 1, 0, 0),
                simd_float4(0, 0, 1, 0),
                simd_float4(translation.x, translation.y, translation.z, 1)
            )
        )
        
        self = translationMatrix * rotationMatrix * scaleMatrix
    }
}

// Efficient circular buffer for queue implementation
struct CircularBuffer<T> {
    private var buffer: [T?]
    private var head = 0
    private var tail = 0
    
    init(capacity: Int) {
        buffer = Array(repeating: nil, count: capacity)
    }
    
    mutating func push(_ element: T) {
        buffer[tail] = element
        tail = (tail + 1) % buffer.count
    }
    
    mutating func pop() -> T? {
        guard let element = buffer[head] else { return nil }
        buffer[head] = nil
        head = (head + 1) % buffer.count
        return element
    }
}

extension simd_float4 {
    var xyz: simd_float3 {
        simd_float3(x, y, z)
    }
}
