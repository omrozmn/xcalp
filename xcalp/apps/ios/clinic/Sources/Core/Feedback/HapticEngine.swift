import CoreHaptics
import Foundation

public final class HapticEngine {
    private var engine: CHHapticEngine?
    private var engineNeedsStart = true
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    
    // Haptic Pattern Definitions
    private let successPattern = """
    {
        "version": 1.0,
        "patterns": [{
            "event": {
                "time": 0.0,
                "eventType": "hapticTransient",
                "intensity": 1.0,
                "sharpness": 0.5
            }
        }, {
            "event": {
                "time": 0.1,
                "eventType": "hapticTransient",
                "intensity": 0.8,
                "sharpness": 0.3
            }
        }]
    }
    """
    
    private let warningPattern = """
    {
        "version": 1.0,
        "patterns": [{
            "event": {
                "time": 0.0,
                "eventType": "hapticTransient",
                "intensity": 1.0,
                "sharpness": 1.0
            }
        }, {
            "time": 0.1,
            "eventType": "hapticContinuous",
            "intensity": 0.5,
            "sharpness": 0.5,
            "duration": 0.25
        }]
    }
    """
    
    public init() throws {
        try createEngine()
    }
    
    // MARK: - Public Interface
    
    public func playPattern(_ pattern: HapticPattern) {
        do {
            switch pattern {
            case .singleTap:
                try playTransientPattern(intensity: 0.8, sharpness: 0.5)
            case .doubleTap:
                try playDoubleTapPattern()
            case .success:
                try playCustomPattern(successPattern)
            case .warning:
                try playCustomPattern(warningPattern)
            case .error:
                try playErrorPattern()
            case .continuousFeedback:
                try startContinuousFeedback()
            case .dynamicFeedback:
                try startDynamicFeedback()
            }
        } catch {
            print("Haptic playback error: \(error.localizedDescription)")
        }
    }
    
    public func updateIntensity(_ intensity: Float) {
        guard let player = continuousPlayer else { return }
        
        do {
            let intensityParameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: intensity,
                relativeTime: 0
            )
            try player.sendParameters([intensityParameter])
        } catch {
            print("Failed to update haptic intensity: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
    }
    
    // MARK: - Private Methods
    
    private func createEngine() throws {
        engine = try CHHapticEngine()
        
        engine?.stoppedHandler = { reason in
            print("Haptic engine stopped: \(reason)")
            self.engineNeedsStart = true
        }
        
        engine?.resetHandler = {
            print("Haptic engine reset")
            self.engineNeedsStart = true
        }
        
        try engine?.start()
    }
    
    private func ensureEngineRunning() throws {
        if engineNeedsStart {
            try engine?.start()
            engineNeedsStart = false
        }
    }
    
    private func playTransientPattern(intensity: Float, sharpness: Float) throws {
        try ensureEngineRunning()
        
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: 0)
    }
    
    private func playDoubleTapPattern() throws {
        try ensureEngineRunning()
        
        let firstTap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0
        )
        
        let secondTap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0.1
        )
        
        let pattern = try CHHapticPattern(events: [firstTap, secondTap], parameters: [])
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: 0)
    }
    
    private func playErrorPattern() throws {
        try ensureEngineRunning()
        
        let sharpTap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ],
            relativeTime: 0
        )
        
        let buzz = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ],
            relativeTime: 0.1,
            duration: 0.3
        )
        
        let pattern = try CHHapticPattern(events: [sharpTap, buzz], parameters: [])
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: 0)
    }
    
    private func startContinuousFeedback() throws {
        try ensureEngineRunning()
        
        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: 100 // Long duration, will be stopped manually
        )
        
        let pattern = try CHHapticPattern(events: [continuous], parameters: [])
        continuousPlayer = try engine?.makeAdvancedPlayer(with: pattern)
        try continuousPlayer?.start(atTime: 0)
    }
    
    private func startDynamicFeedback() throws {
        try ensureEngineRunning()
        
        let dynamicPattern = try createDynamicPattern()
        continuousPlayer = try engine?.makeAdvancedPlayer(with: dynamicPattern)
        try continuousPlayer?.start(atTime: 0)
    }
    
    private func createDynamicPattern() throws -> CHHapticPattern {
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.3),
                .init(relativeTime: 0.5, value: 0.8),
                .init(relativeTime: 1.0, value: 0.3)
            ],
            relativeTime: 0
        )
        
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: 1.0
        )
        
        return try CHHapticPattern(events: [event], parameterCurves: [curve])
    }
    
    private func playCustomPattern(_ jsonPattern: String) throws {
        try ensureEngineRunning()
        
        let pattern = try CHHapticPattern(dictionary: jsonPattern.data(using: .utf8)!)
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: 0)
    }
}