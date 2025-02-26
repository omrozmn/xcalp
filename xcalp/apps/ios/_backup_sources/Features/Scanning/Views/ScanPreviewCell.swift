import UIKit
import SceneKit
import SnapKit

class ScanPreviewCell: UICollectionViewCell {
    private let sceneView = SCNView()
    private let dateLabel = UILabel()
    private let scanTypeLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.1
        
        // Scene View
        contentView.addSubview(sceneView)
        sceneView.backgroundColor = .systemGray6
        sceneView.layer.cornerRadius = 12
        sceneView.clipsToBounds = true
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = true
        
        // Labels
        let labelStack = UIStackView(arrangedSubviews: [dateLabel, scanTypeLabel])
        labelStack.axis = .vertical
        labelStack.spacing = 4
        contentView.addSubview(labelStack)
        
        dateLabel.font = .systemFont(ofSize: 14, weight: .medium)
        scanTypeLabel.font = .systemFont(ofSize: 12)
        scanTypeLabel.textColor = .secondaryLabel
        
        // Layout
        sceneView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(180)
        }
        
        labelStack.snp.makeConstraints { make in
            make.top.equalTo(sceneView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().offset(-8)
        }
    }
    
    func configure(with scan: (SCNGeometry, ScanMetadata)) {
        let (mesh, metadata) = scan
        
        // Configure scene
        let scene = SCNScene()
        let node = SCNNode(geometry: mesh)
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.8)
        node.geometry?.firstMaterial?.isDoubleSided = true
        scene.rootNode.addChildNode(node)
        
        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        
        // Configure lighting
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
        
        sceneView.scene = scene
        
        // Configure labels
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: metadata.date)
        scanTypeLabel.text = "3D Scan v\(metadata.version)"
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        sceneView.scene = nil
    }
}