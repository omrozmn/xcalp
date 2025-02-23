import Combine
import ARKit

class AdaptiveTransitionManager {
    private let qualityPipeline: QualityAssessmentPipeline
    private var transitionSubscriptions = Set<AnyCancellable>()
    private var currentMode: ScanningModes = .lidarOnly
    private var transitionHistory: [TransitionEvent] = []
    private let maxHistoryLength = 10
    
    init(qualityPipeline: QualityAssessmentPipeline) {
        self.qualityPipeline = qualityPipeline
        setupTransitionMonitoring()
    }
    
    private func setupTransitionMonitoring() {
        qualityPipeline.subscribeToQualityUpdates()
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] metrics in
                self?.handleQualityUpdate(metrics)
            }
            .store(in: &transitionSubscriptions)
    }
    
    private func handleQualityUpdate(_ metrics: QualityMetrics) {
        let proposedMode = determineOptimalMode(metrics)
        
        if shouldTransition(to: proposedMode, from: currentMode, metrics: metrics) {
            executeTransition(to: proposedMode, metrics: metrics)
        }
    }
    
    private func determineOptimalMode(_ metrics: QualityMetrics) -> ScanningModes {
        // Consider transition history to prevent oscillation
        if hasRecentOscillation() {
            return currentMode // Stick to current mode to prevent rapid switching
        }
        
        // Normal mode determination logic
        if metrics.fusionQuality >= ScanningQualityThresholds.fusionConfidenceThreshold {
            return .hybridFusion
        }
        
        if metrics.lidarQuality >= ScanningQualityThresholds.minimumLidarConfidence {
            return .lidarOnly
        }
        
        return .photogrammetryOnly
    }
    
    private func shouldTransition(to proposedMode: ScanningModes, from currentMode: ScanningModes, metrics: QualityMetrics) -> Bool {
        // Don't transition if the change is too small
        let qualityImprovement = getQualityImprovement(from: currentMode, to: proposedMode, metrics: metrics)
        if qualityImprovement < 0.2 { // 20% improvement threshold
            return false
        }
        
        // Check if we've had too many recent transitions
        if hasExcessiveTransitions() {
            return false
        }
        
        return true
    }
    
    private func executeTransition(to newMode: ScanningModes, metrics: QualityMetrics) {
        // Record transition
        let event = TransitionEvent(
            from: currentMode,
            to: newMode,
            timestamp: Date(),
            metrics: metrics
        )
        recordTransition(event)
        
        // Update current mode
        currentMode = newMode
        
        // Notify system of transition
        NotificationCenter.default.post(
            name: Notification.Name("ScanningModeTransition"),
            object: nil,
            userInfo: [
                "mode": newMode,
                "reason": getTransitionReason(event)
            ]
        )
    }
    
    private func getQualityImprovement(from currentMode: ScanningModes, to proposedMode: ScanningModes, metrics: QualityMetrics) -> Float {
        let currentQuality = getQualityForMode(currentMode, metrics: metrics)
        let proposedQuality = getQualityForMode(proposedMode, metrics: metrics)
        return proposedQuality - currentQuality
    }
    
    private func getQualityForMode(_ mode: ScanningModes, metrics: QualityMetrics) -> Float {
        switch mode {
        case .lidarOnly:
            return metrics.lidarQuality
        case .photogrammetryOnly:
            return metrics.photoQuality
        case .hybridFusion:
            return metrics.fusionQuality
        }
    }
    
    private func hasRecentOscillation() -> Bool {
        guard transitionHistory.count >= 4 else { return false }
        
        // Check last 4 transitions for oscillation pattern
        let recentTransitions = Array(transitionHistory.suffix(4))
        return recentTransitions[0].to == recentTransitions[2].to &&
               recentTransitions[1].to == recentTransitions[3].to &&
               recentTransitions[0].to != recentTransitions[1].to
    }
    
    private func hasExcessiveTransitions() -> Bool {
        guard transitionHistory.count >= 3 else { return false }
        
        // Check if we've had more than 3 transitions in the last 5 seconds
        let recentTransitions = transitionHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -5
        }
        return recentTransitions.count >= 3
    }
    
    private func recordTransition(_ event: TransitionEvent) {
        transitionHistory.append(event)
        if transitionHistory.count > maxHistoryLength {
            transitionHistory.removeFirst()
        }
    }
    
    private func getTransitionReason(_ event: TransitionEvent) -> String {
        switch event.to {
        case .lidarOnly:
            return "Switched to LiDAR due to superior point cloud quality"
        case .photogrammetryOnly:
            return "Switched to Photogrammetry due to insufficient LiDAR data"
        case .hybridFusion:
            return "Enabled fusion mode due to high confidence in both data sources"
        }
    }
}

struct TransitionEvent {
    let from: ScanningModes
    let to: ScanningModes
    let timestamp: Date
    let metrics: QualityMetrics
}