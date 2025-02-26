import CoreHaptics
import UIKit

public class HapticFeedback {
    public static let shared = HapticFeedback()
    
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var isEngineRunning = false
    
    private init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            isEngineRunning = true
            
            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
                self.isEngineRunning = false
            }
            
            engine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                do {
                    try self?.engine?.start()
                    self?.isEngineRunning = true
                } catch {
                    print("Failed to restart haptic engine: \(error)")
                }
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    public func playQualityFeedback(_ quality: Float) {
        guard isEngineRunning else { return }
        
        let intensity = quality < 0.3 ? 1.0 : quality < 0.7 ? 0.5 : 0.3
        let sharpness = quality < 0.3 ? 0.8 : quality < 0.7 ? 0.5 : 0.3
        
        do {
            let intensityParameter = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: Float(intensity)
            )
            let sharpnessParameter = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: Float(sharpness)
            )
            
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParameter, sharpnessParameter],
                relativeTime: 0
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play quality haptic: \(error)")
        }
    }
    
    public func playCoverageFeedback(_ coverage: Float) {
        guard isEngineRunning else { return }
        
        do {
            let continuousIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: coverage
            )
            let continuousSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: coverage < 0.5 ? 0.8 : 0.4
            )
            
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [continuousIntensity, continuousSharpness],
                relativeTime: 0,
                duration: 0.5
            )
            
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            if continuousPlayer == nil {
                continuousPlayer = try engine?.makeAdvancedPlayer(with: pattern)
            }
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play coverage haptic: \(error)")
        }
    }
    
    public func playSuccessFeedback() {
        guard isEngineRunning else { return }
        
        do {
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
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
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play success haptic: \(error)")
        }
    }
    
    public func playErrorFeedback() {
        guard isEngineRunning else { return }
        
        do {
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
                )
            ]
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play error haptic: \(error)")
        }
    }
    
    public func stopAllHaptics() {
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to stop haptics: \(error)")
        }
    }
}