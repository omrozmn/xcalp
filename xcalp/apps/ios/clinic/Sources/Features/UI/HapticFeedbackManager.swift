import UIKit
import CoreHaptics

public final class HapticFeedbackManager {
    public static let shared = HapticFeedbackManager()
    
    private var engine: CHHapticEngine?
    
    public enum FeedbackType {
        case success
        case warning
        case error
        case selection
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case custom(intensity: Float, sharpness: Float)
    }
    
    init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            // Restart the engine if it stops due to system events
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            
            // Handle engine stopping
            engine?.stoppedHandler = { reason in
                print("Haptic engine stopped: \(reason)")
            }
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    public func playFeedback(_ type: FeedbackType) {
        switch type {
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            
        case .impact(let style):
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
            
        case .custom(let intensity, let sharpness):
            playCustomFeedback(intensity: intensity, sharpness: sharpness)
        }
    }
    
    public func playCustomFeedback(intensity: Float, sharpness: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        let intensityParameter = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: intensity
        )
        let sharpnessParameter = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: sharpness
        )
        
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParameter, sharpnessParameter],
            relativeTime: 0
        )
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    public func playPatternFeedback(_ events: [HapticEvent]) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        let hapticEvents = events.map { event in
            CHHapticEvent(
                eventType: event.type.chHapticEventType,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
                ],
                relativeTime: event.relativeTime
            )
        }
        
        do {
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
}

public struct HapticEvent {
    public let type: EventType
    public let intensity: Float
    public let sharpness: Float
    public let relativeTime: TimeInterval
    
    public enum EventType {
        case transient
        case continuous
        
        var chHapticEventType: CHHapticEvent.EventType {
            switch self {
            case .transient:
                return .hapticTransient
            case .continuous:
                return .hapticContinuous
            }
        }
    }
}

// Preset haptic patterns
extension HapticFeedbackManager {
    public static let successPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.7, sharpness: 0.5, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 1.0, sharpness: 0.7, relativeTime: 0.1)
    ]
    
    public static let warningPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.8, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.8, relativeTime: 0.2)
    ]
    
    public static let errorPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 1.0, sharpness: 1.0, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 1.0, sharpness: 1.0, relativeTime: 0.1),
        HapticEvent(type: .transient, intensity: 1.0, sharpness: 1.0, relativeTime: 0.2)
    ]
    
    public static let scanProgressPattern: [HapticEvent] = [
        HapticEvent(type: .continuous, intensity: 0.5, sharpness: 0.3, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 0.7, sharpness: 0.5, relativeTime: 0.5),
        HapticEvent(type: .continuous, intensity: 0.3, sharpness: 0.2, relativeTime: 1.0)
    ]
    
    public static let templateSelectionPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.6, sharpness: 0.4, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.6, relativeTime: 0.15)
    ]
}

// SwiftUI View extension for haptic feedback
extension View {
    public func hapticFeedback(_ type: HapticFeedbackManager.FeedbackType) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticFeedbackManager.shared.playFeedback(type)
            }
        )
    }
    
    public func hapticPattern(_ pattern: [HapticEvent]) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticFeedbackManager.shared.playPatternFeedback(pattern)
            }
        )
    }
}