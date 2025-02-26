import AVFoundation

public class VoiceFeedbackManager {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage: String?
    private var lastSpeakTime: TimeInterval = 0
    private let minimumInterval: TimeInterval = 3.0
    
    public var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }
    
    public func speakGuidance(_ message: String) {
        guard isEnabled else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastSpeakTime >= minimumInterval else { return }
        guard message != lastSpokenMessage else { return }
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        synthesizer.speak(utterance)
        
        lastSpokenMessage = message
        lastSpeakTime = currentTime
    }
    
    public func speakQualityFeedback(_ quality: Float) {
        guard isEnabled else { return }
        
        let message: String
        if quality < 0.3 {
            message = "Move closer or adjust lighting"
        } else if quality < 0.7 {
            message = "Keep steady and continue scanning"
        } else {
            message = "Good quality scan"
        }
        
        speakGuidance(message)
    }
    
    public func speakCaptureProgress(_ stage: CaptureProgressManager.CaptureStage) {
        guard isEnabled else { return }
        
        speakGuidance(stage.description)
    }
    
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}