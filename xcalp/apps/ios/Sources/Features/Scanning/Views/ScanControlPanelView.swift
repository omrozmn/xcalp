import UIKit
import SceneKit
import RxSwift
import RxRelay

class ScanControlPanelView: UIView {
    // MARK: - Outputs
    let colorControl = PublishRelay<UIColor>()
    let opacityControl = PublishRelay<Float>()
    let rotationControl = PublishRelay<SCNVector3>()
    
    private let colorWell = UIColorWell()
    private let opacitySlider = UISlider()
    private let rotationDial = RotationDialControl()
    
    private let disposeBag = DisposeBag()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupBindings()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground.withAlphaComponent(0.95)
        
        // Add visual effect for blur
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        addSubview(blurView)
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        let vibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: blurEffect))
        blurView.contentView.addSubview(vibrancyView)
        vibrancyView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // Setup controls
        let controlStack = UIStackView(arrangedSubviews: [
            createControlGroup(title: "Color", control: colorWell),
            createControlGroup(title: "Opacity", control: opacitySlider),
            createControlGroup(title: "Rotation", control: rotationDial)
        ])
        controlStack.axis = .horizontal
        controlStack.distribution = .equalSpacing
        controlStack.spacing = 20
        
        vibrancyView.contentView.addSubview(controlStack)
        controlStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(20)
        }
        
        // Configure controls
        colorWell.selectedColor = .systemBlue
        
        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 1
        opacitySlider.value = 0.8
        
        // Add separator line at top
        let separator = UIView()
        separator.backgroundColor = .separator
        addSubview(separator)
        separator.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
    private func setupBindings() {
        // Color well binding
        colorWell.rx.controlEvent(.valueChanged)
            .map { [weak self] _ in self?.colorWell.selectedColor ?? .systemBlue }
            .bind(to: colorControl)
            .disposed(by: disposeBag)
        
        // Opacity slider binding
        opacitySlider.rx.value
            .bind(to: opacityControl)
            .disposed(by: disposeBag)
        
        // Rotation dial binding
        rotationDial.rotationUpdates
            .bind(to: rotationControl)
            .disposed(by: disposeBag)
    }
    
    private func createControlGroup(title: String, control: UIView) -> UIView {
        let container = UIView()
        
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        
        container.addSubview(label)
        container.addSubview(control)
        
        label.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        
        control.snp.makeConstraints { make in
            make.top.equalTo(label.snp.bottom).offset(8)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        
        return container
    }
}

// MARK: - RotationDialControl

private class RotationDialControl: UIControl {
    let rotationUpdates = PublishRelay<SCNVector3>()
    
    private var startAngle: CGFloat = 0
    private var currentRotation = SCNVector3Zero
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: 60, height: 60)
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        
        // Draw outer circle
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(2)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()
        
        // Draw dial indicator
        context.setFillColor(UIColor.systemBlue.cgColor)
        let indicatorRadius: CGFloat = 4
        let indicatorCenter = CGPoint(
            x: center.x + (radius - 8) * cos(startAngle),
            y: center.y + (radius - 8) * sin(startAngle)
        )
        context.addArc(center: indicatorCenter, radius: indicatorRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.fillPath()
    }
    
    private func setupGestureRecognizer() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        switch gesture.state {
        case .began:
            startAngle = atan2(location.y - center.y, location.x - center.x)
            
        case .changed:
            let currentAngle = atan2(location.y - center.y, location.x - center.x)
            let angleDelta = currentAngle - startAngle
            
            // Update rotation based on gesture direction
            currentRotation.y += Float(angleDelta)
            
            // Normalize angle and update start position
            startAngle = currentAngle
            
            // Notify rotation update
            rotationUpdates.accept(currentRotation)
            
            // Trigger redraw
            setNeedsDisplay()
            
        default:
            break
        }
    }
}