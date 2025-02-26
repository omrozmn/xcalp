import UIKit
import ARKit
import RxSwift
import SceneKit

class ScanViewController: UIViewController {
    private let sceneView = ARSCNView()
    private let qualityIndicatorView = ScanQualityIndicatorView()
    private let captureButton = UIButton(type: .system)
    private let disposeBag = DisposeBag()
    
    private let pointCloudProcessor = PointCloudProcessor()
    private let meshGenerator = MeshGenerator()
    private var isScanning = false
    
    private var scanConfiguration: ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        return configuration
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupARSession()
        setupBindings()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sceneView.session.run(scanConfiguration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func setupUI() {
        view.addSubview(sceneView)
        view.addSubview(qualityIndicatorView)
        view.addSubview(captureButton)
        
        sceneView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        qualityIndicatorView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.centerX.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(40)
        }
        
        captureButton.snp.makeConstraints { make in
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-30)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(70)
        }
        
        setupCaptureButton()
        setupGuidanceOverlay()
    }
    
    private func setupGuidanceOverlay() {
        let guidanceView = ScanGuidanceOverlayView()
        view.addSubview(guidanceView)
        guidanceView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupARSession() {
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.showsStatistics = true
    }
    
    private func setupBindings() {
        captureButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.startScanCapture()
            })
            .disposed(by: disposeBag)
    }
    
    private func setupCaptureButton() {
        captureButton.backgroundColor = .systemBlue
        captureButton.layer.cornerRadius = 35
        captureButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        captureButton.tintColor = .white
    }
    
    private func startScanCapture() {
        isScanning = true
        pointCloudProcessor.reset()
        captureButton.isEnabled = false
        
        // Show progress indicator
        let progressHUD = UIActivityIndicatorView(style: .large)
        view.addSubview(progressHUD)
        progressHUD.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        progressHUD.startAnimating()
        
        // Process scan data
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Get current frame depth data
            guard let frame = self.sceneView.session.currentFrame,
                  let depthData = frame.sceneDepth else {
                self.showScanError()
                return
            }
            
            // Process point cloud
            guard self.pointCloudProcessor.processDepthData(depthData) else {
                self.showScanError()
                return
            }
            
            // Generate mesh
            let points = self.pointCloudProcessor.getProcessedPointCloud()
            guard let mesh = self.meshGenerator.generateMesh(from: points) else {
                self.showScanError()
                return
            }
            
            DispatchQueue.main.async {
                progressHUD.removeFromSuperview()
                self.isScanning = false
                self.captureButton.isEnabled = true
                self.showScanPreview(mesh: mesh)
            }
        }
    }
    
    private func showScanError() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(
                title: "Scan Failed",
                message: "Unable to process scan data. Please try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
            
            self.isScanning = false
            self.captureButton.isEnabled = true
        }
    }
    
    private func showScanPreview(mesh: SCNGeometry) {
        let previewVC = ScanPreviewViewController(scannedMesh: mesh)
        navigationController?.pushViewController(previewVC, animated: true)
    }
}

extension ScanViewController: ARSCNViewDelegate, ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle session errors
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Handle session interruption
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Handle interruption end
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isScanning,
              let depthData = frame.sceneDepth else { return }
        
        // Update scan quality indicators in real-time
        let coverage = calculateScanCoverage(depthData)
        let density = calculatePointDensity(depthData)
        
        DispatchQueue.main.async {
            self.qualityIndicatorView.updateMetrics(coverage: coverage, density: density)
            self.captureButton.isEnabled = coverage > 0.7 && density > 0.5
        }
    }
    
    private func calculateScanCoverage(_ depthData: ARDepthData) -> Float {
        // Calculate percentage of valid depth pixels
        var validPixels = 0
        let totalPixels = depthData.depthMap.width * depthData.depthMap.height
        
        for row in 0..<depthData.depthMap.height {
            for col in 0..<depthData.depthMap.width {
                if let depth = depthData.depthMap.value(at: (row, col)),
                   depth > 0 {
                    validPixels += 1
                }
            }
        }
        
        return Float(validPixels) / Float(totalPixels)
    }
    
    private func calculatePointDensity(_ depthData: ARDepthData) -> Float {
        // Calculate average point density
        var totalDepth: Float = 0
        var validPoints = 0
        
        for row in 0..<depthData.depthMap.height {
            for col in 0..<depthData.depthMap.width {
                if let depth = depthData.depthMap.value(at: (row, col)),
                   depth > 0 {
                    totalDepth += depth
                    validPoints += 1
                }
            }
        }
        
        guard validPoints > 0 else { return 0 }
        let averageDepth = totalDepth / Float(validPoints)
        
        // Normalize density based on expected range (30cm - 100cm)
        return 1.0 - ((averageDepth - 0.3) / 0.7).clamped(to: 0...1)
    }
}