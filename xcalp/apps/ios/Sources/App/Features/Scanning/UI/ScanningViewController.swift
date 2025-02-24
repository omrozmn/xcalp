import UIKit
import ARKit
import Metal
import MetalKit

class ScanningViewController: UIViewController {
    private let scanningController = ScanningController()
    private let errorHandler = XCErrorHandler.shared
    private let performanceMonitor = XCPerformanceMonitor.shared
    
    private var arView: ARView!
    private var qualityIndicatorView: QualityIndicatorView!
    private var controlPanel: ScanControlPanel!
    
    private var isScanning = false
    private var currentQualityMetrics: QualityMetrics?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureARView()
    }
    
    private func setupUI() {
        // Setup AR view
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        
        // Setup quality indicator
        qualityIndicatorView = QualityIndicatorView(frame: CGRect(x: 20, y: 60, width: 120, height: 40))
        view.addSubview(qualityIndicatorView)
        
        // Setup control panel
        controlPanel = ScanControlPanel(frame: CGRect(x: 0, y: view.bounds.height - 180, width: view.bounds.width, height: 180))
        controlPanel.delegate = self
        view.addSubview(controlPanel)
        
        setupGestures()
    }
    
    private func configureARView() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorHandler.handle(ScanningError.deviceNotSupported, severity: .critical)
            showDeviceNotSupportedAlert()
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = .sceneDepth
        
        arView.session.delegate = self
        arView.session.run(configuration)
    }
    
    private func setupGestures() {
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotationGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        // Handle model rotation
        guard let node = arView.focusedNode else { return }
        node.eulerAngles.y += Float(gesture.rotation)
        gesture.rotation = 0
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // Handle model scaling
        guard let node = arView.focusedNode else { return }
        node.scale *= Float(gesture.scale)
        gesture.scale = 1
    }
    
    private func startScanning() {
        performanceMonitor.startMeasuring("ScanSession")
        isScanning = true
        controlPanel.updateUI(for: .scanning)
        
        scanningController.startScanning()
    }
    
    private func stopScanning() {
        isScanning = false
        controlPanel.updateUI(for: .processing)
        
        processScanResults()
    }
    
    private func processScanResults() {
        guard let meshProcessor = try? MeshProcessor() else {
            errorHandler.handle(MeshProcessingError.processingTimeout, severity: .high)
            return
        }
        
        // Process the scanned point cloud
        meshProcessor.processMesh(arView.capturedPoints) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let processedMesh):
                    self.displayProcessedMesh(processedMesh)
                    self.controlPanel.updateUI(for: .complete)
                case .failure(let error):
                    self.errorHandler.handle(error, severity: .high)
                    self.controlPanel.updateUI(for: .error)
                }
                
                self.performanceMonitor.stopMeasuring("ScanSession")
            }
        }
    }
    
    private func displayProcessedMesh(_ mesh: ProcessedMesh) {
        // Create and display the processed mesh
        let geometry = createMeshGeometry(from: mesh)
        let node = SCNNode(geometry: geometry)
        arView.scene.rootNode.addChildNode(node)
    }
    
    private func createMeshGeometry(from mesh: ProcessedMesh) -> SCNGeometry {
        let vertices = mesh.vertices
        let indices = mesh.indices
        let normals = mesh.normals
        
        let vertexSource = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
        
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
    
    private func updateQualityIndicator(with metrics: QualityMetrics) {
        currentQualityMetrics = metrics
        qualityIndicatorView.update(with: metrics)
    }
    
    private func showDeviceNotSupportedAlert() {
        let alert = UIAlertController(
            title: "Device Not Supported",
            message: "This device does not support the required AR features for scanning.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - ARSessionDelegate
extension ScanningViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }
        
        // Update quality metrics
        if let metrics = scanningController.getCurrentQualityMetrics() {
            updateQualityIndicator(with: metrics)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        errorHandler.handle(error, severity: .high)
        controlPanel.updateUI(for: .error)
    }
}

// MARK: - ScanControlPanelDelegate
extension ScanningViewController: ScanControlPanelDelegate {
    func controlPanelDidRequestStartScan(_ panel: ScanControlPanel) {
        startScanning()
    }
    
    func controlPanelDidRequestStopScan(_ panel: ScanControlPanel) {
        stopScanning()
    }
    
    func controlPanelDidRequestReset(_ panel: ScanControlPanel) {
        arView.session.run(arView.session.configuration!, options: [.resetTracking, .removeExistingAnchors])
        controlPanel.updateUI(for: .ready)
    }
}