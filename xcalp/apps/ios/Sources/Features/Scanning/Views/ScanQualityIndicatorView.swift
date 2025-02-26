import UIKit
import SnapKit

class ScanQualityIndicatorView: UIView {
    private let coverageLabel = UILabel()
    private let densityLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 20
        
        addSubview(coverageLabel)
        addSubview(densityLabel)
        addSubview(progressView)
        
        coverageLabel.textColor = .white
        densityLabel.textColor = .white
        progressView.progressTintColor = .systemGreen
        
        coverageLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.top.equalToSuperview().offset(8)
        }
        
        densityLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalToSuperview().offset(8)
        }
        
        progressView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.bottom.equalToSuperview().offset(-8)
            make.height.equalTo(4)
        }
    }
    
    func updateMetrics(coverage: Float, density: Float) {
        coverageLabel.text = String(format: "Coverage: %.0f%%", coverage * 100)
        densityLabel.text = String(format: "Density: %.0f%%", density * 100)
        progressView.progress = min(coverage, density)
        
        updateProgressColor(quality: min(coverage, density))
    }
    
    private func updateProgressColor(quality: Float) {
        let color: UIColor
        switch quality {
        case 0..<0.5:
            color = .systemRed
        case 0.5..<0.8:
            color = .systemYellow
        default:
            color = .systemGreen
        }
        progressView.progressTintColor = color
    }
}