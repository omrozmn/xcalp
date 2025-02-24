import UIKit

class TrialStatusView: UIView {
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .bold)
        return label
    }()
    
    private let phaseLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        return label
    }()
    
    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.progressTintColor = .systemBlue
        progress.trackTintColor = .systemGray5
        return progress
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.1
        
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        [titleLabel, phaseLabel, progressLabel, progressView].forEach {
            stackView.addArrangedSubview($0)
        }
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    
    func configure(with trial: TrialConfiguration) {
        titleLabel.text = "Trial ID: \(trial.trialId)"
        
        let phase = trial.phase
        phaseLabel.text = "Phase: \(phase.rawValue.capitalized)"
        
        switch phase {
        case .preparation:
            progressView.progress = 0.0
            progressLabel.text = "Trial setup in progress"
            progressView.progressTintColor = .systemBlue
            
        case .recruitment:
            let progress = Float(calculateRecruitmentProgress(trial))
            progressView.progress = progress
            progressLabel.text = "Recruitment: \(Int(progress * 100))%"
            progressView.progressTintColor = progress < 0.5 ? .systemOrange : .systemBlue
            
        case .dataCollection:
            let progress = Float(calculateDataCollectionProgress(trial))
            progressView.progress = progress
            progressLabel.text = "Data Collection: \(Int(progress * 100))%"
            progressView.progressTintColor = progress < 0.7 ? .systemOrange : .systemGreen
            
        case .analysis:
            let progress = Float(calculateAnalysisProgress(trial))
            progressView.progress = progress
            progressLabel.text = "Analysis: \(Int(progress * 100))%"
            progressView.progressTintColor = .systemBlue
            
        case .validation:
            let progress = Float(calculateValidationProgress(trial))
            progressView.progress = progress
            progressLabel.text = "Validation: \(Int(progress * 100))%"
            progressView.progressTintColor = progress < 0.9 ? .systemOrange : .systemGreen
            
        case .completion:
            progressView.progress = 1.0
            progressLabel.text = "Trial Completed"
            progressView.progressTintColor = .systemGreen
        }
        
        updateAppearance(for: phase)
    }
    
    func showNoActiveTrial() {
        titleLabel.text = "No Active Trial"
        phaseLabel.text = "Status: Inactive"
        progressLabel.text = "Create a new trial to begin"
        progressView.progress = 0.0
        progressView.progressTintColor = .systemGray
        
        backgroundColor = .systemGray6
    }
    
    private func updateAppearance(for phase: TrialPhase) {
        switch phase {
        case .preparation, .recruitment:
            backgroundColor = .systemBlue.withAlphaComponent(0.1)
        case .dataCollection:
            backgroundColor = .systemGreen.withAlphaComponent(0.1)
        case .analysis, .validation:
            backgroundColor = .systemOrange.withAlphaComponent(0.1)
        case .completion:
            backgroundColor = .systemGreen.withAlphaComponent(0.1)
        }
    }
    
    private func calculateRecruitmentProgress(_ trial: TrialConfiguration) -> Double {
        // Implementation would fetch actual recruitment data
        return 0.5 // Placeholder
    }
    
    private func calculateDataCollectionProgress(_ trial: TrialConfiguration) -> Double {
        // Implementation would calculate based on required data points
        return 0.7 // Placeholder
    }
    
    private func calculateAnalysisProgress(_ trial: TrialConfiguration) -> Double {
        // Implementation would track analysis completion
        return 0.8 // Placeholder
    }
    
    private func calculateValidationProgress(_ trial: TrialConfiguration) -> Double {
        // Implementation would track validation status
        return 0.9 // Placeholder
    }
}