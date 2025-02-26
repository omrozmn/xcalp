import UIKit
import CoreHaptics
import SwiftUI

public class HapticFeedbackManager {
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private var intensityParameter: CHHapticDynamicParameter?
    private var sharpnessParameter: CHHapticDynamicParameter?
    
    public init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            // Handle engine stop
            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
                try? self.engine?.start()
            }
            
            // Handle engine reset
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                try? self?.engine?.start()
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    public func playQualityFeedback(_ quality: Float) {
        // Provide continuous feedback based on scan quality
        do {
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: quality
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: quality > 0.7 ? 0.8 : 0.4
            )
            
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: 0.15
            )
            
            try playHapticPattern([event])
        } catch {
            // Fallback to basic haptics
            impactGenerator.impactOccurred(intensity: quality)
        }
    }
    
    public func playScanningComplete() {
        do {
            // Create success pattern
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: 0.1
                )
            ]
            
            try playHapticPattern(events)
        } catch {
            // Fallback to basic haptics
            notificationGenerator.notificationOccurred(.success)
        }
    }
    
    public func playError() {
        do {
            // Create error pattern
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0.1
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: 0.2
                )
            ]
            
            try playHapticPattern(events)
        } catch {
            // Fallback to basic haptics
            notificationGenerator.notificationOccurred(.error)
        }
    }
    
    public func playProgressFeedback(_ progress: Float) {
        guard progress.truncatingRemainder(dividingBy: 0.25) < 0.01 else { return }
        selectionGenerator.selectionChanged()
    }
    
    public func playCoverageFeedback(_ coverage: Float) {
        // Provide intensity based on coverage completeness
        do {
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: coverage
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: coverage > 0.8 ? 0.9 : 0.5
            )
            
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0
            )
            
            try playHapticPattern([event])
        } catch {
            impactGenerator.impactOccurred(intensity: coverage)
        }
    }
    
    private func playHapticPattern(_ events: [CHHapticEvent]) throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
    }
    
    public func startContinuousFeedback() {
        do {
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.5
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.5
            )
            
            intensityParameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: 0.5,
                relativeTime: 0
            )
            
            sharpnessParameter = CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: 0.5,
                relativeTime: 0
            )
            
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: 100 // Long duration
            )
            
            let pattern = try CHHapticPattern(
                events: [event],
                parameters: [intensityParameter!, sharpnessParameter!]
            )
            
            continuousPlayer = try engine?.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: 0)
        } catch {
            print("Failed to start continuous feedback: \(error)")
        }
    }
    
    public func updateContinuousFeedback(intensity: Float, sharpness: Float) {
        do {
            try continuousPlayer?.sendParameters([
                CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: intensity,
                    relativeTime: 0
                ),
                CHHapticDynamicParameter(
                    parameterID: .hapticSharpnessControl,
                    value: sharpness,
                    relativeTime: 0
                )
            ])
        } catch {
            print("Failed to update continuous feedback: \(error)")
        }
    }
    
    public func stopContinuousFeedback() {
        continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
    }
}