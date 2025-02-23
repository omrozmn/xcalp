import ARKit
import Combine

class QualityAssessmentPipeline {
    private let qualityCalculator = QualityMetricsCalculator()
    private var qualitySubscriptions = Set<AnyCancellable>()
    private let qualitySubject = PassthroughSubject<QualityMetrics, Never>()
    private let transitionThreshold: TimeInterval = 0.5 // seconds
    private var lastTransitionTime: Date = Date()
    
    // Quality streams
    private let lidarQualityStream = PassthroughSubject<Float, Never>()
    private let photoQualityStream = PassthroughSubject<Float, Never>()
    private let fusionQualityStream = PassthroughSubject<Float, Never>()
    
    init() {
        setupQualityPipeline()
    }
    
    func startMonitoring() {
        // Start quality assessment streams
        monitorLidarQuality()
        monitorPhotogrammetryQuality()
        monitorFusionQuality()
    }
    
    private func setupQualityPipeline() {
        // Combine quality streams with debounce to prevent rapid transitions
        Publishers.CombineLatest3(
            lidarQualityStream.debounce(for: .seconds(0.2), scheduler: DispatchQueue.main),
            photoQualityStream.debounce(for: .seconds(0.2), scheduler: DispatchQueue.main),
            fusionQualityStream.debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
        )
        .map { lidarQuality, photoQuality, fusionQuality in
            QualityMetrics(
                lidarQuality: lidarQuality,
                photoQuality: photoQuality,
                fusionQuality: fusionQuality,
                timestamp: Date()
            )
        }
        .sink { [weak self] metrics in
            self?.processQualityMetrics(metrics)
        }
        .store(in: &qualitySubscriptions)
    }
    
    private func processQualityMetrics(_ metrics: QualityMetrics) {
        guard Date().timeIntervalSince(lastTransitionTime) >= transitionThreshold else {
            return // Prevent too frequent transitions
        }
        
        let recommendedMode = determineOptimalMode(metrics)
        qualitySubject.send(metrics)
        
        if shouldTransition(to: recommendedMode, given: metrics) {
            lastTransitionTime = Date()
            NotificationCenter.default.post(
                name: Notification.Name("ScanningModeTransition"),
                object: nil,
                userInfo: ["mode": recommendedMode]
            )
        }
    }
    
    private func determineOptimalMode(_ metrics: QualityMetrics) -> ScanningModes {
        if metrics.fusionQuality >= ScanningQualityThresholds.fusionConfidenceThreshold {
            return .hybridFusion
        }
        
        if metrics.lidarQuality >= metrics.photoQuality {
            return .lidarOnly
        }
        
        return .photogrammetryOnly
    }
    
    private func shouldTransition(to mode: ScanningModes, given metrics: QualityMetrics) -> Bool {
        switch mode {
        case .lidarOnly:
            return metrics.lidarQuality >= ScanningQualityThresholds.minimumLidarConfidence
        case .photogrammetryOnly:
            return metrics.photoQuality >= ScanningQualityThresholds.minimumPhotogrammetryConfidence
        case .hybridFusion:
            return metrics.fusionQuality >= ScanningQualityThresholds.fusionConfidenceThreshold
        }
    }
    
    func subscribeToQualityUpdates() -> AnyPublisher<QualityMetrics, Never> {
        return qualitySubject.eraseToAnyPublisher()
    }
}

struct QualityMetrics {
    let lidarQuality: Float
    let photoQuality: Float
    let fusionQuality: Float
    let timestamp: Date
}