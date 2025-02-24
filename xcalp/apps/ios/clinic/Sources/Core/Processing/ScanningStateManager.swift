import Foundation
import os.log
import Core.Constants
import Core.Services.Analytics

public final class ScanningStateManager {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningState")
    private let userDefaults = UserDefaults.standard
    private let telemetryQueue = DispatchQueue(label: "com.xcalp.clinic.telemetry", qos: .utility)
    
    // State persistence keys
    private enum Keys {
        static let lastScanningMode = "lastScanningMode"
        static let qualityMetrics = "qualityMetrics"
        static let sessionHistory = "sessionHistory"
    }
    
    // In-memory state
    private var currentQualityMetrics: [String: Float] = [:]
    
    struct TransitionEvent {
        let from: ScanningModes
        let to: ScanningModes
        let timestamp: Date
        let trigger: String
    }
    
    private var transitionHistory: [TransitionEvent] = []
    
    public func persistCurrentMode(_ mode: ScanningModes) {
        userDefaults.set(mode.rawValue, forKey: Keys.lastScanningMode)
    }
    
    public func retrieveLastMode() -> ScanningModes? {
        guard let modeString = userDefaults.string(forKey: Keys.lastScanningMode),
              let mode = ScanningModes(rawValue: modeString) else {
            return nil
        }
        return mode
    }
    
    public func logModeTransition(from oldMode: ScanningModes, to newMode: ScanningModes, trigger: String) {
        telemetryQueue.async {
            self.transitionHistory.append(TransitionEvent(from: oldMode, to: newMode, timestamp: Date(), trigger: trigger))
            self.logTransitionTelemetry(from: oldMode, to: newMode, trigger: trigger)
        }
    }
    
    public func updateQualityMetrics(_ metrics: [String: Float]) {
        currentQualityMetrics = metrics
        userDefaults.set(metrics, forKey: Keys.qualityMetrics)
        
        telemetryQueue.async {
            self.logQualityMetrics(metrics)
        }
    }
    
    public func getTransitionHistory() -> [TransitionEvent] {
        return transitionHistory
    }
    
    private func logTransitionTelemetry(from oldMode: ScanningModes, to newMode: ScanningModes, trigger: String) {
        logger.info("""
            Mode transition:
            From: \(oldMode.rawValue)
            To: \(newMode.rawValue)
            Trigger: \(trigger)
            Quality metrics: \(String(describing: currentQualityMetrics))
            """)
        
        // Log to analytics service
        AnalyticsService.shared.logEvent(
            "scanning_mode_transition",
            parameters: [
                "from_mode": oldMode.rawValue,
                "to_mode": newMode.rawValue,
                "trigger": trigger,
                "quality_metrics": currentQualityMetrics
            ]
        )
    }
    
    private func logQualityMetrics(_ metrics: [String: Float]) {
        logger.info("Quality metrics updated: \(metrics)")
        
        AnalyticsService.shared.logEvent(
            "scanning_quality_update",
            parameters: metrics
        )
    }
}
