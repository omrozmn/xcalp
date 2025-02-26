import UIKit
import SceneKit
import RxSwift

class ScanPreviewViewController: UIViewController {
    private let sceneView = SCNView()
    private let saveButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private let disposeBag = DisposeBag()
    
    private let scannedMesh: SCNGeometry
    
    init(scannedMesh: SCNGeometry) {
        self.scannedMesh = scannedMesh
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupScene()
        setupBindings()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Setup SceneView
        view.addSubview(sceneView)
        sceneView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // Setup buttons
        let buttonStack = UIStackView(arrangedSubviews: [retakeButton, saveButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.distribution = .fillEqually
        
        view.addSubview(buttonStack)
        buttonStack.snp.makeConstraints { make in
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-20)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.height.equalTo(44)
        }
        
        saveButton.setTitle("Save Scan", for: .normal)
        saveButton.backgroundColor = .systemBlue
        saveButton.layer.cornerRadius = 22
        saveButton.setTitleColor(.white, for: .normal)
        
        retakeButton.setTitle("Retake", for: .normal)
        retakeButton.backgroundColor = .systemGray5
        retakeButton.layer.cornerRadius = 22
    }
    
    private func setupScene() {
        let scene = SCNScene()
        
        // Create node with scanned mesh
        let meshNode = SCNNode(geometry: scannedMesh)
        meshNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
        meshNode.geometry?.firstMaterial?.isDoubleSided = true
        scene.rootNode.addChildNode(meshNode)
        
        // Add lighting
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 100
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.intensity = 800
        let omniNode = SCNNode()
        omniNode.light = omniLight
        omniNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(omniNode)
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        
        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.backgroundColor = .systemBackground
        sceneView.autoenablesDefaultLighting = true
    }
    
    private func setupBindings() {
        saveButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.saveScan()
            })
            .disposed(by: disposeBag)
        
        retakeButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)
    }
    
    private func saveScan() {
        // Show saving indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        view.addSubview(activityIndicator)
        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        activityIndicator.startAnimating()
        
        // Disable buttons while saving
        saveButton.isEnabled = false
        retakeButton.isEnabled = false
        
        // Save scan data
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // TODO: Implement scan data persistence
            // For now, we'll just simulate a save operation
            Thread.sleep(forTimeInterval: 1.0)
            
            DispatchQueue.main.async {
                activityIndicator.removeFromSuperview()
                self?.showSaveSuccess()
            }
        }
    }
    
    private func showSaveSuccess() {
        let alert = UIAlertController(
            title: "Scan Saved",
            message: "The 3D scan has been saved successfully.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popToRootViewController(animated: true)
        })
        present(alert, animated: true)
    }
}