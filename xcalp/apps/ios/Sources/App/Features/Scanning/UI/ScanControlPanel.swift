import UIKit

protocol ScanControlPanelDelegate: AnyObject {
    func controlPanelDidRequestStartScan(_ panel: ScanControlPanel)
    func controlPanelDidRequestStopScan(_ panel: ScanControlPanel)
    func controlPanelDidRequestReset(_ panel: ScanControlPanel)
}

class ScanControlPanel: UIView {
    enum ScanningState {
        case ready
        case scanning
        case processing
        case complete
        case error
    }
    
    weak var delegate: ScanControlPanelDelegate?
    private var currentState: ScanningState = .ready
    
    // MARK: - UI Components
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.distribution = .fillEqually
        return stack
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        return label
    }()
    
    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.layer.cornerRadius = 12
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Reset", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemGray
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private let modeSelector: UISegmentedControl = {
        let items = ["LiDAR", "Photo", "Hybrid"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.backgroundColor = .systemGray6
        return control
    }()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.8)
        layer.cornerRadius = 16
        clipsToBounds = true
        
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(modeSelector)
        stackView.addArrangedSubview(actionButton)
        stackView.addArrangedSubview(resetButton)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
        
        updateUI(for: .ready)
    }
    
    // MARK: - State Management
    func updateUI(for state: ScanningState) {
        currentState = state
        
        switch state {
        case .ready:
            statusLabel.text = "Ready to Scan"
            actionButton.setTitle("Start Scan", for: .normal)
            actionButton.backgroundColor = .systemBlue
            modeSelector.isEnabled = true
            resetButton.isEnabled = true
            
        case .scanning:
            statusLabel.text = "Scanning in Progress..."
            actionButton.setTitle("Stop Scan", for: .normal)
            actionButton.backgroundColor = .systemRed
            modeSelector.isEnabled = false
            resetButton.isEnabled = false
            
        case .processing:
            statusLabel.text = "Processing Scan..."
            actionButton.setTitle("Processing...", for: .normal)
            actionButton.backgroundColor = .systemGray
            actionButton.isEnabled = false
            modeSelector.isEnabled = false
            resetButton.isEnabled = false
            
        case .complete:
            statusLabel.text = "Scan Complete"
            actionButton.setTitle("New Scan", for: .normal)
            actionButton.backgroundColor = .systemGreen
            actionButton.isEnabled = true
            modeSelector.isEnabled = true
            resetButton.isEnabled = true
            
        case .error:
            statusLabel.text = "Scan Error"
            actionButton.setTitle("Retry Scan", for: .normal)
            actionButton.backgroundColor = .systemOrange
            actionButton.isEnabled = true
            modeSelector.isEnabled = true
            resetButton.isEnabled = true
        }
    }
    
    // MARK: - Actions
    @objc private func actionButtonTapped() {
        switch currentState {
        case .ready, .error, .complete:
            delegate?.controlPanelDidRequestStartScan(self)
        case .scanning:
            delegate?.controlPanelDidRequestStopScan(self)
        case .processing:
            break // Button is disabled in this state
        }
    }
    
    @objc private func resetButtonTapped() {
        delegate?.controlPanelDidRequestReset(self)
    }
    
    // MARK: - Public Methods
    func getCurrentScanningMode() -> ScanningController.ScanningMode {
        switch modeSelector.selectedSegmentIndex {
        case 0:
            return .lidar
        case 1:
            return .photogrammetry
        case 2:
            return .hybrid
        default:
            return .lidar
        }
    }
}