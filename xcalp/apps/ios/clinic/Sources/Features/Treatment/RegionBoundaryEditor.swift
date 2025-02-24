import ARKit
import SceneKit
import SwiftUI

struct RegionBoundaryEditor: View {
    @Binding var boundaries: [Point3D]
    let modelURL: URL?
    
    @State private var selectedPoint: Int?
    @State private var isDrawing = false
    @State private var sceneView: SCNView?
    @State private var hitTestPlane: SCNNode?
    
    // Visual feedback
    @State private var hoveredPoint: SCNVector3?
    @State private var projectedLine: SCNNode?
    @State private var guidePoints: [SCNNode] = []
    @State private var regionPreview: SCNNode?
    
    var body: some View {
        SceneViewContainer(
            sceneView: $sceneView,
            scene: makeScene(),
            pointOfView: makeCamera(),
            options: [.allowsCameraControl, .autoenablesDefaultLighting],
            delegate: RegionSceneDelegate(
                onHover: { point in
                    hoveredPoint = point
                    updateVisualGuides()
                }
            )
        )
        .overlay(alignment: .topLeading) {
            drawingControls
        }
        .overlay(alignment: .bottomTrailing) {
            if boundaries.count >= 3 {
                areaDisplay
            }
        }
        .onAppear {
            setupHitTestPlane()
            setupVisualGuides()
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isDrawing else { return }
                    handleDrag(at: value.location)
                }
        )
    }
    
    private var drawingControls: some View {
        VStack {
            Button(isDrawing ? "Finish Drawing" : "Draw Region") {
                isDrawing.toggle()
                if !isDrawing && boundaries.count >= 3 {
                    boundaries.append(boundaries[0]) // Close the loop
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            if !boundaries.isEmpty {
                Button("Clear", role: .destructive) {
                    boundaries.removeAll()
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            
            if isDrawing {
                Button("Undo") {
                    if !boundaries.isEmpty {
                        boundaries.removeLast()
                    }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .disabled(boundaries.isEmpty)
            }
        }
    }
    
    private var areaDisplay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Points: \(boundaries.count)")
                .font(.caption)
            if let area = calculateArea() {
                Text(String(format: "Area: %.1f cm²", area))
                    .font(.caption)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .padding()
    }
    
    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        
        // Add model if available
if let modelURL = modelURL {
            if let modelNode = try? SCNReferenceNode(url: modelURL) {
                modelNode.load()
                
                // Scale and center the model
                let (min, max) = modelNode.boundingBox
                let extents = SCNVector3(max.x - min.x, max.y - min.y, max.z - min.z)
                let maxExtent = max(extents.x, extents.y, extents.z)
                let scale = 2.0 / Float(maxExtent) // Scale to fit in a 2x2x2 box
                modelNode.scale = SCNVector3(scale, scale, scale)
                
                // Center the model
                modelNode.position = SCNVector3(
                    -(min.x + extents.x / 2) * scale,
                    -(min.y + extents.y / 2) * scale,
                    -(min.z + extents.z / 2) * scale
                )
                
                scene.rootNode.addChildNode(modelNode)
            }
        }
        
        // Add boundary visualization
        let boundaryNode = createBoundaryNode()
        scene.rootNode.addChildNode(boundaryNode)
        
        return scene
    }
    
    private func createBoundaryNode() -> SCNNode {
        let boundaryNode = SCNNode()
        
        // Add points
        for (index, point) in boundaries.enumerated() {
            let sphere = SCNSphere(radius: 0.02)
            sphere.firstMaterial?.diffuse.contents = index == selectedPoint ? UIColor.yellow : UIColor.blue
            
            let pointNode = SCNNode(geometry: sphere)
            pointNode.position = SCNVector3(point.x, point.y, point.z)
            boundaryNode.addChildNode(pointNode)
            
            // Add lines between points
            if index > 0 {
                let previousPoint = boundaries[index - 1]
                let line = createLine(from: previousPoint, to: point)
                boundaryNode.addChildNode(line)
            }
        }
        
        // Close the loop if we have enough points and not drawing
        if boundaries.count >= 3, !isDrawing {
            let line = createLine(from: boundaries.last!, to: boundaries[0])
            boundaryNode.addChildNode(line)
        }
        
        return boundaryNode
    }
    
    private func setupHitTestPlane() {
        guard let sceneView = sceneView else { return }
        
        // Create a transparent plane for hit testing
        let plane = SCNPlane(width: 10, height: 10)
        plane.firstMaterial?.diffuse.contents = UIColor.clear
        plane.firstMaterial?.isDoubleSided = true
        
        hitTestPlane = SCNNode(geometry: plane)
        hitTestPlane?.eulerAngles.x = -.pi / 2 // Rotate to horizontal
        
        sceneView.scene?.rootNode.addChildNode(hitTestPlane!)
    }
    
    private func handleDrag(at location: CGPoint) {
        guard let sceneView = sceneView else { return }
        
        // Perform hit testing with the model first
        let modelHitResults = sceneView.hitTest(location, options: [
            .boundingBoxOnly: true,
            .searchMode: SCNHitTestSearchMode.closest.rawValue
        ])
        
        if let result = modelHitResults.first {
            let hitPoint = result.worldCoordinates
            addPoint(Point3D(
                x: Double(hitPoint.x),
                y: Double(hitPoint.y),
                z: Double(hitPoint.z)
            ))
            return
        }
        
        // If no model hit, try the hit test plane
        if let hitTestPlane = hitTestPlane {
            let planeHitResults = sceneView.hitTest(
                location,
                with: hitTestPlane
            )
            
            if let result = planeHitResults.first {
                let hitPoint = result.worldCoordinates
                addPoint(Point3D(
                    x: Double(hitPoint.x),
                    y: Double(hitPoint.y),
                    z: Double(hitPoint.z)
                ))
            }
        }
    }
    
    private func addPoint(_ point: Point3D) {
        if let selectedPoint = selectedPoint {
            // Update existing point
            boundaries[selectedPoint] = point
        } else {
            // Add new point
            boundaries.append(point)
        }
    }
    
    private func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 5)
        
        return cameraNode
    }
    
    private func createLine(from start: Point3D, to end: Point3D) -> SCNNode {
        let startVector = SCNVector3(start.x, start.y, start.z)
        let endVector = SCNVector3(end.x, end.y, end.z)
        
        let height = CGFloat(GLKVector3Distance(
            GLKVector3Make(Float(startVector.x), Float(startVector.y), Float(startVector.z)),
            GLKVector3Make(Float(endVector.x), Float(endVector.y), Float(endVector.z))
        ))
        
        let cylinder = SCNCylinder(radius: 0.005, height: height)
        cylinder.firstMaterial?.diffuse.contents = UIColor.blue
        
        let node = SCNNode(geometry: cylinder)
        
        let startPoint = GLKVector3Make(Float(startVector.x), Float(startVector.y), Float(startVector.z))
        let endPoint = GLKVector3Make(Float(endVector.x), Float(endVector.y), Float(endVector.z))
        
        // Position and orient the cylinder
        let vector = GLKVector3Subtract(endPoint, startPoint)
        let midPoint = GLKVector3MultiplyScalar(GLKVector3Add(startPoint, endPoint), 0.5)
        
        node.position = SCNVector3(midPoint.x, midPoint.y, midPoint.z)
        node.eulerAngles = SCNVector3Make(
            Float(atan2(Double(vector.z), sqrt(Double(vector.x * vector.x + vector.y * vector.y)))),
            Float(atan2(Double(vector.y), Double(vector.x))),
            0
        )
        
        return node
    }
    
    // MARK: - Visual Guides
    
    private func setupVisualGuides() {
        guard let sceneView = sceneView else { return }
        
        // Create guide points (shown when hovering)
        let guideGeometry = SCNSphere(radius: 0.01)
        guideGeometry.firstMaterial?.diffuse.contents = UIColor.gray.withAlphaComponent(0.5)
        
        for _ in 0...20 {
            let node = SCNNode(geometry: guideGeometry)
            node.opacity = 0
            sceneView.scene?.rootNode.addChildNode(node)
            guidePoints.append(node)
        }
        
        // Create projected line
        let lineGeometry = SCNCylinder(radius: 0.002, height: 1.0)
        lineGeometry.firstMaterial?.diffuse.contents = UIColor.gray.withAlphaComponent(0.3)
        
        projectedLine = SCNNode(geometry: lineGeometry)
        projectedLine?.opacity = 0
        sceneView.scene?.rootNode.addChildNode(projectedLine!)
        
        // Create region preview
        regionPreview = SCNNode()
        regionPreview?.opacity = 0.3
        sceneView.scene?.rootNode.addChildNode(regionPreview!)
    }
    
    private func updateVisualGuides() {
        guard let hoveredPoint = hoveredPoint else {
            hideGuides()
            return
        }
        
        // Update guide points
        if boundaries.isEmpty {
            // Show circular guide
            showCircularGuide(around: hoveredPoint)
        } else {
            // Show linear guide between last point and hover
            showLinearGuide(to: hoveredPoint)
        }
        
        // Update region preview
        updateRegionPreview()
    }
    
    private func showCircularGuide(around center: SCNVector3) {
        let radius: Float = 0.1
        let pointCount = min(20, guidePoints.count)
        
        for (index, node) in guidePoints.enumerated() {
            if index < pointCount {
                let angle = Float(index) * (2 * .pi / Float(pointCount))
                node.position = SCNVector3(
                    center.x + radius * cos(angle),
                    center.y,
                    center.z + radius * sin(angle)
                )
                node.opacity = 1
            } else {
                node.opacity = 0
            }
        }
        
        projectedLine?.opacity = 0
    }
    
    private func showLinearGuide(to point: SCNVector3) {
        guard let lastPoint = boundaries.last.map({ SCNVector3($0.x, $0.y, $0.z) }) else { return }
        
        // Hide guide points except for division points
        let divisions = 10
        let vector = SCNVector3(
            point.x - lastPoint.x,
            point.y - lastPoint.y,
            point.z - lastPoint.z
        )
        
        for (index, node) in guidePoints.enumerated() {
            if index < divisions {
                let t = Float(index + 1) / Float(divisions)
                node.position = SCNVector3(
                    lastPoint.x + vector.x * t,
                    lastPoint.y + vector.y * t,
                    lastPoint.z + vector.z * t
                )
                node.opacity = 1
            } else {
                node.opacity = 0
            }
        }
        
        // Show projected line
        updateProjectedLine(from: lastPoint, to: point)
    }
    
    private func updateProjectedLine(from start: SCNVector3, to end: SCNVector3) {
        let distance = sqrt(
            pow(end.x - start.x, 2) +
            pow(end.y - start.y, 2) +
            pow(end.z - start.z, 2)
        )
        
        projectedLine?.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        
        projectedLine?.look(at: end, up: .init(0, 1, 0), localFront: .init(0, 0, 1))
        projectedLine?.scale = SCNVector3(1, CGFloat(distance), 1)
        projectedLine?.opacity = 1
    }
    
    private func hideGuides() {
        guidePoints.forEach { $0.opacity = 0 }
        projectedLine?.opacity = 0
        regionPreview?.opacity = 0
    }
    
    private func updateRegionPreview() {
        guard boundaries.count >= 2, let hoveredPoint = hoveredPoint else {
            regionPreview?.opacity = 0
            return
        }
        
        var points = boundaries.map { SCNVector3($0.x, $0.y, $0.z) }
        points.append(SCNVector3(hoveredPoint.x, hoveredPoint.y, hoveredPoint.z))
        
        if let previewGeometry = createRegionPreviewGeometry(from: points) {
            regionPreview?.geometry = previewGeometry
            regionPreview?.opacity = 0.3
        }
    }
    
    private func createRegionPreviewGeometry(from points: [SCNVector3]) -> SCNGeometry? {
        guard points.count >= 3 else { return nil }
        
        // Create vertices
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        
        // Add center point (average of all points)
        let center = points.reduce(SCNVector3Zero) { sum, point in
            SCNVector3(sum.x + point.x, sum.y + point.y, sum.z + point.z)
        }
        let centerPoint = SCNVector3(
            center.x / Float(points.count),
            center.y / Float(points.count),
            center.z / Float(points.count)
        )
        
        vertices.append(centerPoint)
        
        // Add boundary points
        vertices.append(contentsOf: points)
        
        // Create triangles
        for i in 0..<points.count {
            indices.append(0) // Center point
            indices.append(Int32(i + 1))
            indices.append(Int32((i + 1) % points.count + 1))
        }
        
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: indices,
            primitiveType: .triangles
        )
        
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.blue.withAlphaComponent(0.3)
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
    
    private func calculateArea() -> Double? {
        guard boundaries.count >= 3 else { return nil }
        
        // Use shoelace formula to calculate area
        var area: Double = 0
        for i in 0..<boundaries.count {
            let j = (i + 1) % boundaries.count
            let point1 = boundaries[i]
            let point2 = boundaries[j]
            
            area += point1.x * point2.z - point2.x * point1.z
        }
        
        return abs(area) / 2
    }
}

private class RegionSceneDelegate: NSObject, SCNSceneRendererDelegate {
    let onHover: (SCNVector3) -> Void
    
    init(onHover: @escaping (SCNVector3) -> Void) {
        self.onHover = onHover
        super.init()
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let sceneView = renderer as? SCNView,
              let camera = sceneView.pointOfView else { return }
        
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let hitResults = sceneView.hitTest(center, options: [
            .boundingBoxOnly: true,
            .searchMode: SCNHitTestSearchMode.closest.rawValue
        ])
        
        if let result = hitResults.first {
            onHover(result.worldCoordinates)
        }
    }
}

private struct SceneViewContainer: UIViewRepresentable {
    @Binding var sceneView: SCNView?
    let scene: SCNScene
    let pointOfView: SCNNode
    let options: SCNView.Options
    let delegate: SCNSceneRendererDelegate
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.backgroundColor = .systemBackground
        view.defaultRenderingAPI = .metal
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = true
        view.delegate = delegate
        
        for (key, value) in options {
            view.setValue(value, forKey: key)
        }
        
        sceneView = view
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        uiView.pointOfView = pointOfView
    }
}

extension SCNView {
    func hitTest(with node: SCNNode) -> [SCNHitTestResult] {
        guard let camera = pointOfView?.camera else { return [] }
        
        let viewPort = bounds.size
        let p1 = CGPoint(x: 0, y: 0)
        let p2 = CGPoint(x: viewPort.width, y: viewPort.height)
        
        guard let startPoint = unprojectPoint(SCNVector3Zero),
              let endPoint = unprojectPoint(SCNVector3(x: 1, y: 1, z: 1)) else {
            return []
        }
        
        let options: [String: Any] = [
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
            SCNHitTestOption.rootNode.rawValue: node
        ]
        
        return hitTest(convert(p1, to: nil), options: options) +
               hitTest(convert(p2, to: nil), options: options)
    }
}
