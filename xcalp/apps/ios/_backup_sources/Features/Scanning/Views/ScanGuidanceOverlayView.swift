import UIKit

class ScanGuidanceOverlayView: UIView {
    private let instructionLabel = UILabel()
    private let guidanceImageView = UIImageView()
    private var currentInstruction = 0
    private var timer: Timer?
    
    private let instructions = [
        ("Position the device 30-40cm from the head", "distance"),
        ("Slowly move around to capture all angles", "rotation"),
        ("Keep the head centered in frame", "center"),
        ("Maintain steady movement for best results", "steady")
    ]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        startGuidance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Setup instruction label
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.font = .systemFont(ofSize: 17, weight: .medium)
        instructionLabel.textColor = .white
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.clipsToBounds = true
        
        addSubview(instructionLabel)
        instructionLabel.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide).offset(20)
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().offset(-40)
            make.height.greaterThanOrEqualTo(44)
        }
        
        // Setup guidance image view
        guidanceImageView.contentMode = .scaleAspectFit
        guidanceImageView.tintColor = .white
        
        addSubview(guidanceImageView)
        guidanceImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(instructionLabel.snp.bottom).offset(20)
            make.width.height.equalTo(100)
        }
    }
    
    private func startGuidance() {
        updateGuidance()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.nextInstruction()
        }
    }
    
    private func nextInstruction() {
        currentInstruction = (currentInstruction + 1) % instructions.count
        updateGuidance()
    }
    
    private func updateGuidance() {
        let (text, imageName) = instructions[currentInstruction]
        
        UIView.transition(with: instructionLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.instructionLabel.text = text
        }
        
        UIView.transition(with: guidanceImageView, duration: 0.3, options: .transitionCrossDissolve) {
            self.guidanceImageView.image = UIImage(systemName: imageName)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 60, weight: .medium))
        }
    }
    
    func stopGuidance() {
        timer?.invalidate()
        timer = nil
    }
    
    override func removeFromSuperview() {
        stopGuidance()
        super.removeFromSuperview()
    }
}