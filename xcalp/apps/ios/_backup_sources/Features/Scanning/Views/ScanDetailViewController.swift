import UIKit
import SceneKit
import RxSwift

class ScanDetailViewController: UIViewController {
    private let sceneView = SCNView()
    private let controlPanel = ScanControlPanelView()
    private let disposeBag = DisposeBag()
    
    private let mesh: SCNGeometry
    private let metadata: ScanMetadata
    private var currentNode: SCNNode?
    
    init(mesh: SCNGeometry, metadata: ScanMetadata) {
        self.mesh = mesh
        self.metadata = metadata
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
        title = "Scan Details"
        view.backgroundColor = .systemBackground
        
        // Add scene view
        view.addSubview(sceneView)
        sceneView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        sceneView.backgroundColor = .systemBackground
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        
        // Add control panel
        view.addSubview(controlPanel)
        controlPanel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(120)
        }
        
        // Add info button
        let infoButton = UIBarButtonItem(image: UIImage(systemName: "info.circle"),
                                       style: .plain,
                                       target: nil,
                                       action: nil)
        navigationItem.rightBarButtonItem = infoButton
        
        infoButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.showScanInfo()
            })
            .disposed(by: disposeBag)
    }
    
    private func setupScene() {
        let scene = SCNScene()
        
        // Add mesh node
        let node = SCNNode(geometry: mesh)
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
        node.geometry?.firstMaterial?.isDoubleSided = true
        scene.rootNode.addChildNode(node)
        currentNode = node
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        
        // Setup lighting
        setupLighting(in: scene)
        
        sceneView.scene = scene
    }
    
    private func setupLighting(in scene: SCNScene) {
        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 100
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Omni light
        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.intensity = 800
        let omniNode = SCNNode()
        omniNode.light = omniLight
        omniNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(omniNode)
    }
    
    private func setupBindings() {
        // Control panel bindings
        controlPanel.colorControl
            .subscribe(onNext: { [weak self] color in
                self?.updateMeshColor(color)
            })
            .disposed(by: disposeBag)
        
        controlPanel.opacityControl
            .subscribe(onNext: { [weak self] opacity in
                self?.updateMeshOpacity(opacity)
            })
            .disposed(by: disposeBag)
        
        controlPanel.rotationControl
            .subscribe(onNext: { [weak self] rotation in
                self?.updateMeshRotation(rotation)
            })
            .disposed(by: disposeBag)
    }
    
    private func updateMeshColor(_ color: UIColor) {
        currentNode?.geometry?.firstMaterial?.diffuse.contents = color
    }
    
    private func updateMeshOpacity(_ opacity: Float) {
        currentNode?.geometry?.firstMaterial?.transparency = CGFloat(opacity)
    }
    
    private func updateMeshRotation(_ rotation: SCNVector3) {
        currentNode?.eulerAngles = rotation
    }
    
    private func showScanInfo() {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        
        let alert = UIAlertController(
            title: "Scan Information",
            message: """
                Scan ID: \(metadata.id)
                Patient ID: \(metadata.patientId)
                Date: \(formatter.string(from: metadata.date))
                Version: \(metadata.version)
                """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}