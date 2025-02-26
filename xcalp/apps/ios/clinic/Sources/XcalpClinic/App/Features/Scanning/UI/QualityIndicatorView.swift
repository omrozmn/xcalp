import UIKit

class QualityIndicatorView: UIView {
    private let qualityLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.progressTintColor = .systemGreen
        progress.trackTintColor = .systemGray
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
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 8
        clipsToBounds = true
        
        addSubview(qualityLabel)
        addSubview(progressView)
        
        qualityLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            qualityLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            qualityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            qualityLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            progressView.topAnchor.constraint(equalTo: qualityLabel.bottomAnchor, constant: 4),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    func update(with metrics: QualityMetrics) {
        // Calculate overall quality score (0-100)
        let qualityScore = calculateQualityScore(metrics)
        
        // Update UI
        qualityLabel.text = "Scan Quality: \(Int(qualityScore))%"
        progressView.progress = Float(qualityScore) / 100.0
        
        // Update color based on quality
        progressView.progressTintColor = colorForQuality(qualityScore)
    }
    
    private func calculateQualityScore(_ metrics: QualityMetrics) -> Double {
        // Weight different metrics to calculate overall quality
        let densityWeight = 0.3
        let completenessWeight = 0.3
        let noiseWeight = 0.2
        let preservationWeight = 0.2
        
        // Normalize metrics to 0-100 scale
        let densityScore = min(Double(metrics.pointDensity) / 750.0 * 100, 100) // 750 points/cm² is target
        let completenessScore = Double(metrics.surfaceCompleteness)
        let noiseScore = (1.0 - Double(metrics.noiseLevel) / 0.1) * 100 // 0.1mm is max acceptable noise
        let preservationScore = Double(metrics.featurePreservation)
        
        // Calculate weighted average
        let score = densityScore * densityWeight +
                   completenessScore * completenessWeight +
                   noiseScore * noiseWeight +
                   preservationScore * preservationWeight
        
        return min(max(score, 0), 100)
    }
    
    private func colorForQuality(_ score: Double) -> UIColor {
        switch score {
        case 0..<60:
            return .systemRed
        case 60..<80:
            return .systemYellow
        default:
            return .systemGreen
        }
    }
}