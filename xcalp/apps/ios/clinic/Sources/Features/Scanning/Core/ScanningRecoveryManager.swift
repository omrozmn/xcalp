import Foundation
import RealityKit
import ARKit

public class ScanningRecoveryManager {
    public enum RecoveryAction {
        case relocalize
        case restart
        case adjustLighting
        case moveCloser
        case moveFarther
        case clearObstructions
        case reduceMovement
        case none
    }
    
    public struct RecoveryStep {
        let action: RecoveryAction
        let description: String
        let priority: Int
        var isComplete: Bool
    }
    
    private var lastKnownPoints: [Point3D] = []
    private var lastKnownQuality: Float = 0.0
    private var recoveryAttempts = 0
    private let maxRecoveryAttempts = 3
    
    private var onRecoveryStarted: (() -> Void)?
    private var onRecoveryProgress: ((Float) -> Void)?
    private var onRecoveryCompleted: ((Bool) -> Void)?
    
    private var currentIssues: Set<ScanningQualityError> = []
    private var recoverySteps: [RecoveryStep] = []
    private var lastTrackingState: ARCamera.TrackingState?
    private var consecutiveTrackingFailures = 0
    private var isRecoveryInProgress = false
    
    private var onRecoveryUpdate: (([RecoveryStep]) -> Void)?
    
    public init(onRecoveryUpdate: @escaping ([RecoveryStep]) -> Void) {
        self.onRecoveryUpdate = onRecoveryUpdate
    }
    
    public func setRecoveryCallbacks(
        onStarted: @escaping () -> Void,
        onProgress: @escaping (Float) -> Void,
        onCompleted: @escaping (Bool) -> Void
    ) {
        self.onRecoveryStarted = onStarted
        self.onRecoveryProgress = onProgress
        self.onRecoveryCompleted = onCompleted
    }
    
    public func saveState(_ points: [Point3D], quality: Float) {
        lastKnownPoints = points
        lastKnownQuality = quality
    }
    
    public func attemptRecovery() async -> Bool {
        guard recoveryAttempts < maxRecoveryAttempts,
              !lastKnownPoints.isEmpty else {
            return false
        }
        
        recoveryAttempts += 1
        onRecoveryStarted?()
        
        // Attempt to recover scanning state
        do {
            // Try to resume from last known good state
            onRecoveryProgress?(0.3)
            
            // Validate recovered points
            if validateRecoveredState() {
                onRecoveryProgress?(0.7)
                recoveryAttempts = 0
                onRecoveryCompleted?(true)
                return true
            }
            
            onRecoveryCompleted?(false)
            return false
        } catch {
            onRecoveryCompleted?(false)
            return false
        }
    }
    
    private func validateRecoveredState() -> Bool {
        // Ensure we have enough valid points
        guard lastKnownPoints.count >= 100 else { return false }
        
        // Check if the last known quality was acceptable
        guard lastKnownQuality >= 0.5 else { return false }
        
        return true
    }
    
    public func reset() {
        lastKnownPoints.removeAll()
        lastKnownQuality = 0.0
        recoveryAttempts = 0
        currentIssues.removeAll()
        recoverySteps.removeAll()
        lastTrackingState = nil
        consecutiveTrackingFailures = 0
        isRecoveryInProgress = false
        updateRecoverySteps()
    }
    
    public func canAttemptRecovery() -> Bool {
        return recoveryAttempts < maxRecoveryAttempts && !lastKnownPoints.isEmpty
    }
    
    public func handleTrackingFailure(_ camera: ARCamera) {
        guard camera.trackingState != lastTrackingState else { return }
        
        lastTrackingState = camera.trackingState
        
        switch camera.trackingState {
        case .notAvailable:
            handleNotAvailable()
        case .limited(let reason):
            handleLimitedTracking(reason)
        case .normal:
            handleTrackingRecovered()
        }
    }
    
    public func handleQualityIssue(_ error: ScanningQualityError) {
        currentIssues.insert(error)
        updateRecoverySteps()
    }
    
    public func clearIssue(_ error: ScanningQualityError) {
        currentIssues.remove(error)
        updateRecoverySteps()
    }
    
    private func handleNotAvailable() {
        consecutiveTrackingFailures += 1
        
        if consecutiveTrackingFailures > 3 {
            recoverySteps.append(RecoveryStep(
                action: .restart,
                description: "Scanning system unresponsive. Please restart scanning.",
                priority: 5,
                isComplete: false
            ))
        }
        
        updateRecoverySteps()
    }
    
    private func handleLimitedTracking(_ reason: ARCamera.TrackingState.Reason) {
        var newSteps: [RecoveryStep] = []
        
        switch reason {
        case .initializing:
            newSteps.append(RecoveryStep(
                action: .reduceMovement,
                description: "Hold device still while initializing",
                priority: 4,
                isComplete: false
            ))
            
        case .excessiveMotion:
            newSteps.append(RecoveryStep(
                action: .reduceMovement,
                description: "Move the device more slowly",
                priority: 5,
                isComplete: false
            ))
            
        case .insufficientFeatures:
            newSteps.append(contentsOf: [
                RecoveryStep(
                    action: .adjustLighting,
                    description: "Ensure area is well lit",
                    priority: 4,
                    isComplete: false
                ),
                RecoveryStep(
                    action: .moveCloser,
                    description: "Move closer to capture more detail",
                    priority: 3,
                    isComplete: false
                )
            ])
            
        case .relocalizing:
            newSteps.append(RecoveryStep(
                action: .relocalize,
                description: "Move device to a previously scanned area",
                priority: 5,
                isComplete: false
            ))
            
        @unknown default:
            break
        }
        
        recoverySteps = newSteps
        updateRecoverySteps()
    }
    
    private func handleTrackingRecovered() {
        consecutiveTrackingFailures = 0
        recoverySteps.removeAll { $0.action == .relocalize || $0.action == .restart }
        updateRecoverySteps()
    }
    
    private func updateRecoverySteps() {
        // Add steps for quality issues
        var qualitySteps: [RecoveryStep] = []
        
        for issue in currentIssues {
            switch issue {
            case .insufficientLight:
                qualitySteps.append(RecoveryStep(
                    action: .adjustLighting,
                    description: "Area too dark - improve lighting",
                    priority: 4,
                    isComplete: false
                ))
                
            case .tooMuchMotion:
                qualitySteps.append(RecoveryStep(
                    action: .reduceMovement,
                    description: "Motion blur detected - move more slowly",
                    priority: 5,
                    isComplete: false
                ))
                
            case .tooFar:
                qualitySteps.append(RecoveryStep(
                    action: .moveCloser,
                    description: "Move closer to capture more detail",
                    priority: 3,
                    isComplete: false
                ))
                
            case .tooClose:
                qualitySteps.append(RecoveryStep(
                    action: .moveFarther,
                    description: "Move farther to capture full view",
                    priority: 3,
                    isComplete: false
                ))
                
            case .obstruction:
                qualitySteps.append(RecoveryStep(
                    action: .clearObstructions,
                    description: "Remove objects blocking the view",
                    priority: 4,
                    isComplete: false
                ))
            }
        }
        
        // Merge tracking and quality recovery steps
        recoverySteps.append(contentsOf: qualitySteps)
        
        // Sort by priority
        recoverySteps.sort { $0.priority > $1.priority }
        
        // Remove duplicates
        recoverySteps = Array(Set(recoverySteps))
        
        // Notify of updates
        onRecoveryUpdate?(recoverySteps)
    }
    
    public func markStepComplete(_ action: RecoveryAction) {
        if let index = recoverySteps.firstIndex(where: { $0.action == action }) {
            recoverySteps[index].isComplete = true
            updateRecoverySteps()
        }
    }
}