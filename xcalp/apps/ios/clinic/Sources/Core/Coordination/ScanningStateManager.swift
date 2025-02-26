import Foundation
import ARKit
import Combine

public class ScanningStateManager {
    private var stateHistory: [(state: ScanningState, timestamp: Date)] = []
    private var recoveryPoints: [RecoveryPoint] = []
    private var qualityHistory: [QualityMetrics] = []
    private let maxHistorySize = 30
    private let minQualityThreshold: Float = 0.7
    
    private var lastState: ScanningState = .idle
    private var lastQualityMetrics: QualityMetrics?
    private var statePublisher = PassthroughSubject<ScanningState, Never>()
    
    public var stateUpdates: AnyPublisher<ScanningState, Never> {
        statePublisher.eraseToAnyPublisher()
    }
    
    public func updateState(_ newState: ScanningState) {
        stateHistory.append((newState, Date()))
        if stateHistory.count > maxHistorySize {
            stateHistory.removeFirst()
        }
        
        lastState = newState
        statePublisher.send(newState)
        
        if case .scanning = newState {
            checkForRecoveryPoint()
        }
    }
    
    public func updateQualityMetrics(_ metrics: QualityMetrics) {
        qualityHistory.append(metrics)
        if qualityHistory.count > maxHistorySize {
            qualityHistory.removeFirst()
        }
        
        lastQualityMetrics = metrics
        checkQualityTrend()
    }
    
    private func checkQualityTrend() {
        guard qualityHistory.count >= 5 else { return }
        
        let recentMetrics = qualityHistory.suffix(5)
        let averageQuality = recentMetrics.reduce(0) { $0 + $1.surfaceCompleteness } / Float(recentMetrics.count)
        
        if averageQuality > minQualityThreshold {
            createRecoveryPoint()
        }
    }
    
    public func createRecoveryPoint() {
        guard case .scanning = lastState,
              let metrics = lastQualityMetrics,
              metrics.isAcceptable else {
            return
        }
        
        let recoveryPoint = RecoveryPoint(
            timestamp: Date(),
            state: lastState,
            metrics: metrics
        )
        
        recoveryPoints.append(recoveryPoint)
        
        // Keep only recent recovery points
        if recoveryPoints.count > 5 {
            recoveryPoints.removeFirst()
        }
    }
    
    public func findLatestValidRecoveryPoint() -> RecoveryPoint? {
        return recoveryPoints.last { point in
            point.metrics.isAcceptable &&
            Date().timeIntervalSince(point.timestamp) < 30 // Only use recent points
        }
    }
    
    public func getStateTransitionHistory() -> [(from: ScanningState, to: ScanningState, duration: TimeInterval)] {
        guard stateHistory.count > 1 else { return [] }
        
        var transitions: [(ScanningState, ScanningState, TimeInterval)] = []
        for i in 1..<stateHistory.count {
            let previous = stateHistory[i-1]
            let current = stateHistory[i]
            let duration = current.timestamp.timeIntervalSince(previous.timestamp)
            
            transitions.append((previous.state, current.state, duration))
        }
        
        return transitions
    }
    
    public func resetHistory() {
        stateHistory.removeAll()
        recoveryPoints.removeAll()
        qualityHistory.removeAll()
        lastState = .idle
        lastQualityMetrics = nil
    }
}

public struct RecoveryPoint {
    let timestamp: Date
    let state: ScanningState
    let metrics: QualityMetrics
}

public enum ScanningState: Equatable {
    case idle
    case initializing
    case scanning
    case processing
    case paused(reason: PauseReason)
    case recovering(attempt: Int)
    case error(ScanningError)
    case complete
    
    public enum PauseReason: String {
        case qualityLow = "Quality too low"
        case motionExcessive = "Excessive motion"
        case systemResources = "System resources limited"
        case userInitiated = "User paused"
    }
}