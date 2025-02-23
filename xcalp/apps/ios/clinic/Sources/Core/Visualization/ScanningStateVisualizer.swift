import SwiftUI
import ARKit
import SceneKit

class ScanningStateVisualizer {
    private let sceneView: ARSCNView
    private let overlayView: UIView
    private let statusLabel: UILabel
    private let qualityIndicator: UIProgressView
    private var currentState: ScanningState = .initializing
    private var visualizationNodes: [SCNNode] = []
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
        
        // Setup overlay view
        self.overlayView = UIView(frame: .zero)
        overlayView.backgroundColor = .clear
        
        // Setup status label
        self.statusLabel = UILabel(frame: .zero)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.layer.shadowColor = UIColor.black.cgColor
        statusLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        statusLabel.layer.shadowOpacity = 0.5
        
        // Setup quality indicator
        self.qualityIndicator = UIProgressView(progressViewStyle: .bar)
        qualityIndicator.progressTintColor = .systemGreen
        qualityIndicator.trackTintColor = .systemGray
        
        setupUI()
    }
    
    func updateState(_ state: ScanningState, quality: Float) {
        currentState = state
        
        DispatchQueue.main.async { [weak self] in
            self?.updateUI(for: state, quality: quality)
            self?.updateVisualization(for: state)
        }
    }
    
    func visualizePointCloud(_ points: [SIMD3<Float>], color: UIColor) {
        let node = createPointCloudNode(points: points, color: color)
        visualizationNodes.append(node)
        sceneView.scene.rootNode.addChildNode(node)
    }
    
    func clearVisualization() {
        visualizationNodes.forEach { $0.removeFromParentNode() }
        visualizationNodes.removeAll()
    }
    
    private func setupUI() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        qualityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        sceneView.addSubview(overlayView)
        overlayView.addSubview(statusLabel)
        overlayView.addSubview(qualityIndicator)
        
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: sceneView.safeAreaLayoutGuide.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: sceneView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: sceneView.trailingAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 100),
            
            statusLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 20),
            
            qualityIndicator.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 40),
            qualityIndicator.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -40),
            qualityIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            qualityIndicator.heightAnchor.constraint(equalToConstant: 4)
        ])
    }
    
    private func updateUI(for state: ScanningState, quality: Float) {
        statusLabel.text = state.description
        qualityIndicator.progress = quality
        
        // Update colors based on quality
        if quality < 0.3 {
            qualityIndicator.progressTintColor = .systemRed
        } else if quality < 0.7 {
            qualityIndicator.progressTintColor = .systemYellow
        } else {
            qualityIndicator.progressTintColor = .systemGreen
        }
        
        // Animate transition
        UIView.animate(withDuration: 0.3) {
            self.overlayView.alpha = state == .initializing ? 0.0 : 1.0
        }
    }
    
    private func updateVisualization(for state: ScanningState) {
        clearVisualization()
        
        switch state {
        case .lidarScanning:
            addLidarVisualization()
        case .photogrammetryScanning:
            addPhotogrammetryVisualization()
        case .fusion:
            addFusionVisualization()
        case .transitioning(let from, let to):
            addTransitionVisualization(from: from, to: to)
        default:
            break
        }
    }
    
    private func createPointCloudNode(points: [SIMD3<Float>], color: UIColor) -> SCNNode {
        let geometry = SCNGeometry.pointCloud(from: points, color: color)
        return SCNNode(geometry: geometry)
    }
    
    private func addLidarVisualization() {
        // Add real-time LiDAR point cloud visualization
        let lidarNode = SCNNode()
        lidarNode.geometry = SCNGeometry.createConfidenceVisualization()
        visualizationNodes.append(lidarNode)
        sceneView.scene.rootNode.addChildNode(lidarNode)
    }
    
    private func addPhotogrammetryVisualization() {
        // Add feature point visualization for photogrammetry
        let featureNode = SCNNode()
        featureNode.geometry = SCNGeometry.createFeatureVisualization()
        visualizationNodes.append(featureNode)
        sceneView.scene.rootNode.addChildNode(featureNode)
    }
    
    private func addFusionVisualization() {
        // Add blended visualization for fusion mode
        let fusionNode = SCNNode()
        fusionNode.geometry = SCNGeometry.createFusionVisualization()
        visualizationNodes.append(fusionNode)
        sceneView.scene.rootNode.addChildNode(fusionNode)
    }
    
    private func addTransitionVisualization(from: ScanningModes, to: ScanningModes) {
        // Add transition effect
        let transitionNode = SCNNode()
        transitionNode.geometry = SCNGeometry.createTransitionVisualization(from: from, to: to)
        visualizationNodes.append(transitionNode)
        sceneView.scene.rootNode.addChildNode(transitionNode)
    }
}

enum ScanningState {
    case initializing
    case lidarScanning
    case photogrammetryScanning
    case fusion
    case transitioning(from: ScanningModes, to: ScanningModes)
    case failed(reason: String)
    
    var description: String {
        switch self {
        case .initializing:
            return "Initializing Scanner..."
        case .lidarScanning:
            return "LiDAR Scanning Active"
        case .photogrammetryScanning:
            return "Photogrammetry Active"
        case .fusion:
            return "Fusion Mode Active"
        case .transitioning(let from, let to):
            return "Transitioning: \(from.rawValue) → \(to.rawValue)"
        case .failed(let reason):
            return "Scanning Failed: \(reason)"
        }
    }
}

// Extension to create visualization geometries
extension SCNGeometry {
    static func pointCloud(from points: [SIMD3<Float>], color: UIColor) -> SCNGeometry {
        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SCNVector3>.stride)
        
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )
        
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vertices.count,
            bytesPerIndex: 0
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.pointSize = 3
        geometry.materials = [material]
        
        return geometry
    }
    
    static func createConfidenceVisualization() -> SCNGeometry {
        // Implement confidence visualization geometry
        return SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0)
    }
    
    static func createFeatureVisualization() -> SCNGeometry {
        // Implement feature visualization geometry
        return SCNSphere(radius: 0.01)
    }
    
    static func createFusionVisualization() -> SCNGeometry {
        // Implement fusion visualization geometry
        return SCNPyramid(width: 0.1, height: 0.1, length: 0.1)
    }
    
    static func createTransitionVisualization(from: ScanningModes, to: ScanningModes) -> SCNGeometry {
        // Implement transition visualization geometry
        return SCNTorus(ringRadius: 0.1, pipeRadius: 0.01)
    }
}