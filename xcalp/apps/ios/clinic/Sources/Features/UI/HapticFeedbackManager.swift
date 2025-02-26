import CoreHaptics

public final class HapticFeedbackManager {
    public static let shared = HapticFeedbackManager()
    
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var isHapticsEnabled: Bool = true
    private var adaptiveIntensity: Float = 1.0
    private var thermalState: ProcessorThermalState = .nominal
    
    public enum FeedbackType {
        case success
        case warning
        case error
        case selection
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case custom(intensity: Float, sharpness: Float)
    }
    
    public enum ProcessorThermalState {
        case nominal, fair, serious, critical
    }
    
    public struct AdaptiveHapticParameters {
        var baseIntensity: Float
        var baseSharpness: Float
        var duration: TimeInterval
        var dynamicMass: Float
        var decay: Float
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
            
            // Add thermal state monitoring
            #if os(iOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(thermalStateChanged),
                name: ProcessInfo.processInfo.thermalStateDidChangeNotification,
                object: nil
            )
            #endif
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    @objc private func thermalStateChanged() {
        #if os(iOS)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalState = .nominal
            adaptiveIntensity = 1.0
        case .fair:
            thermalState = .fair
            adaptiveIntensity = 0.8
        case .serious:
            thermalState = .serious
            adaptiveIntensity = 0.5
        case .critical:
            thermalState = .critical
            adaptiveIntensity = 0.3
        @unknown default:
            thermalState = .nominal
            adaptiveIntensity = 1.0
        }
        #endif
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
    
    public func startContinuousFeedback(
        intensity: Float,
        sharpness: Float,
        parameters: AdaptiveHapticParameters? = nil
    ) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = engine else { return }
        
        let adjustedIntensity = intensity * adaptiveIntensity
        let adjustedSharpness = sharpness * adaptiveIntensity
        
        do {
            let intensityParameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: adjustedIntensity,
                relativeTime: 0
            )
            
            let sharpnessParameter = CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: adjustedSharpness,
                relativeTime: 0
            )
            
            var events: [CHHapticEvent] = []
            var dynamicParameters: [CHHapticDynamicParameter] = [
                intensityParameter,
                sharpnessParameter
            ]
            
            if let params = parameters {
                // Add adaptive parameters
                events.append(contentsOf: createAdaptiveEvents(params))
                dynamicParameters.append(contentsOf: createAdaptiveDynamicParameters(params))
            } else {
                // Default continuous event
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: adjustedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: adjustedSharpness)
                    ],
                    relativeTime: 0,
                    duration: 100 // Long duration that we'll control dynamically
                ))
            }
            
            let pattern = try CHHapticPattern(events: events, parameters: [])
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            
            try continuousPlayer?.start(atTime: 0)
            
            // Apply dynamic parameters
            try dynamicParameters.forEach { parameter in
                try continuousPlayer?.sendParameters([parameter], atTime: 0)
            }
        } catch {
            print("Failed to start continuous haptic feedback: \(error)")
        }
    }
    
    public func updateContinuousFeedback(intensity: Float, sharpness: Float) {
        guard let player = continuousPlayer else { return }
        
        let adjustedIntensity = intensity * adaptiveIntensity
        let adjustedSharpness = sharpness * adaptiveIntensity
        
        do {
            let intensityParameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: adjustedIntensity,
                relativeTime: 0
            )
            
            let sharpnessParameter = CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: adjustedSharpness,
                relativeTime: 0
            )
            
            try player.sendParameters(
                [intensityParameter, sharpnessParameter],
                atTime: 0
            )
        } catch {
            print("Failed to update continuous haptic feedback: \(error)")
        }
    }
    
    public func stopContinuousFeedback() {
        continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
    }
    
    private func createAdaptiveEvents(_ parameters: AdaptiveHapticParameters) -> [CHHapticEvent] {
        let intensity = parameters.baseIntensity * adaptiveIntensity
        let sharpness = parameters.baseSharpness * adaptiveIntensity
        
        return [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    CHHapticEventParameter(parameterID: .attackTime, value: 0.1),
                    CHHapticEventParameter(parameterID: .decayTime, value: parameters.decay),
                    CHHapticEventParameter(parameterID: .sustained, value: 1.0)
                ],
                relativeTime: 0,
                duration: parameters.duration
            )
        ]
    }
    
    private func createAdaptiveDynamicParameters(_ parameters: AdaptiveHapticParameters) -> [CHHapticDynamicParameter] {
        return [
            CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: parameters.baseIntensity * adaptiveIntensity,
                relativeTime: 0
            ),
            CHHapticDynamicParameter(
                parameterID: .hapticSharpnessControl,
                value: parameters.baseSharpness * adaptiveIntensity,
                relativeTime: 0
            ),
            CHHapticDynamicParameter(
                parameterID: .dynamicMassControl,
                value: parameters.dynamicMass,
                relativeTime: 0
            )
        ]
    }
}

public struct HapticEvent {
    public let type: EventType
    public let intensity: Float
    public let sharpness: Float
    public let relativeTime: TimeInterval
    public var duration: TimeInterval?
    
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
    
    public init(
        type: EventType,
        intensity: Float,
        sharpness: Float,
        relativeTime: TimeInterval,
        duration: TimeInterval? = nil
    ) {
        self.type = type
        self.intensity = intensity
        self.sharpness = sharpness
        self.relativeTime = relativeTime
        self.duration = duration
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
    
    public static let regionSelectionPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.6, sharpness: 0.4, relativeTime: 0),
        HapticEvent(type: .continuous, intensity: 0.3, sharpness: 0.2, relativeTime: 0.1),
        HapticEvent(type: .transient, intensity: 0.7, sharpness: 0.5, relativeTime: 0.2)
    ]

    public static let qualityAlertPattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.7, relativeTime: 0),
        HapticEvent(type: .continuous, intensity: 0.4, sharpness: 0.3, relativeTime: 0.1),
        HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.7, relativeTime: 0.3)
    ]

    public static let measurementCompletePattern: [HapticEvent] = [
        HapticEvent(type: .transient, intensity: 0.5, sharpness: 0.3, relativeTime: 0),
        HapticEvent(type: .transient, intensity: 0.7, sharpness: 0.5, relativeTime: 0.15),
        HapticEvent(type: .transient, intensity: 0.9, sharpness: 0.7, relativeTime: 0.3)
    ]

    public static let scanningProgressPatterns: [Double: [HapticEvent]] = [
        0.25: [
            HapticEvent(type: .transient, intensity: 0.4, sharpness: 0.3, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.2, sharpness: 0.1, relativeTime: 0.1, duration: 0.2)
        ],
        0.5: [
            HapticEvent(type: .transient, intensity: 0.6, sharpness: 0.4, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.3, sharpness: 0.2, relativeTime: 0.1, duration: 0.3)
        ],
        0.75: [
            HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.5, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.4, sharpness: 0.3, relativeTime: 0.1, duration: 0.4)
        ],
        1.0: [
            HapticEvent(type: .transient, intensity: 1.0, sharpness: 0.7, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.5, sharpness: 0.4, relativeTime: 0.1, duration: 0.5),
            HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.6, relativeTime: 0.7)
        ]
    ]
    
    public static let qualityTransitionPattern: [HapticEvent] = [
        HapticEvent(type: .continuous, intensity: 0.5, sharpness: 0.3, relativeTime: 0, duration: 0.4),
        HapticEvent(type: .transient, intensity: 0.7, sharpness: 0.5, relativeTime: 0.4),
        HapticEvent(type: .continuous, intensity: 0.3, sharpness: 0.2, relativeTime: 0.5, duration: 0.3),
        HapticEvent(type: .transient, intensity: 0.9, sharpness: 0.7, relativeTime: 0.8)
    ]
    
    public static let processingStagePatterns: [String: [HapticEvent]] = [
        "start": [
            HapticEvent(type: .transient, intensity: 0.6, sharpness: 0.4, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.3, sharpness: 0.2, relativeTime: 0.1, duration: 0.3)
        ],
        "processing": [
            HapticEvent(type: .continuous, intensity: 0.4, sharpness: 0.3, relativeTime: 0, duration: 0.5),
            HapticEvent(type: .transient, intensity: 0.6, sharpness: 0.4, relativeTime: 0.5)
        ],
        "complete": [
            HapticEvent(type: .transient, intensity: 0.8, sharpness: 0.6, relativeTime: 0),
            HapticEvent(type: .continuous, intensity: 0.5, sharpness: 0.4, relativeTime: 0.1, duration: 0.4),
            HapticEvent(type: .transient, intensity: 1.0, sharpness: 0.7, relativeTime: 0.5)
        ]
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
