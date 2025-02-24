import AVFoundation
import Foundation

public final class VoiceGuidanceManager {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastGuidance: String?
    private let minimumInterval: TimeInterval = 3.0
    private var lastSpeechTime: Date = .distantPast
    
    public static let shared = VoiceGuidanceManager()
    
    private init() {}
    
    public func provideGuidance(for guide: ScanningGuide) {
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) >= minimumInterval else { return }
        
        let guidance = getMessage(for: guide)
        guard guidance != lastGuidance else { return }
        
        speak(guidance)
        lastGuidance = guidance
        lastSpeechTime = now
    }
    
    private func getMessage(for guide: ScanningGuide) -> String {
        switch guide {
        case .preparation:
            return "Please ensure good lighting and a clear view of the patient's head. Hold the device about 30 centimeters away."
            
        case .startPosition:
            return "Position yourself at the front of the patient's head. We'll start scanning from here."
            
        case .scanning:
            return "Slowly move around the patient's head, maintaining a consistent distance. Keep the device steady."
            
        case .qualityWarning:
            return "Scan quality is reducing. Please move more slowly and keep the device steady."
            
        case .coverage(let percentage):
            return "Surface coverage is \(Int(percentage))%. Continue scanning uncovered areas."
            
        case .distanceTooClose:
            return "You're too close to the surface. Please move back slightly."
            
        case .distanceTooFar:
            return "You're too far from the surface. Please move closer."
            
        case .movementTooFast:
            return "Moving too quickly. Please slow down for better quality."
            
        case .lightingTooLow:
            return "The lighting is too dark. Please increase lighting for better scan quality."
            
        case .lightingTooHigh:
            return "The lighting is too bright. Please reduce direct light for better scanning."
            
        case .steadyDevice:
            return "Hold the device more steady to improve scan quality."
            
        case .calibrationNeeded:
            return "LiDAR sensor needs calibration. Please move the device in a figure-eight pattern."
            
        case .scanComplete:
            return "Scan complete. Please wait while we process the data."
            
        case .processingProgress(let progress):
            return "Processing scan data, \(Int(progress * 100))% complete. Please keep the device steady."
            
        case .adjustAngle(let direction):
            switch direction {
            case .tiltUp:
                return "Please tilt the device slightly upward."
            case .tiltDown:
                return "Please tilt the device slightly downward."
            case .rotateLeft:
                return "Please rotate the device slightly to the left."
            case .rotateRight:
                return "Please rotate the device slightly to the right."
            }
            
        case .focusArea(let area):
            return "Please focus on scanning the \(area) area."
            
        case .error(let error):
            return "Error occurred: \(error). Please try again."
        }
    }
    
    private func speak(_ message: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        synthesizer.speak(utterance)
    }
    
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastGuidance = nil
    }
}

public enum ScanningGuide {
    case preparation
    case startPosition
    case scanning
    case qualityWarning
    case coverage(Float)
    case distanceTooClose
    case distanceTooFar
    case movementTooFast
    case lightingTooLow
    case lightingTooHigh
    case steadyDevice
    case calibrationNeeded
    case scanComplete
    case processingProgress(Float)
    case adjustAngle(Direction)
    case focusArea(String)
    case error(String)
    
    public enum Direction {
        case tiltUp
        case tiltDown
        case rotateLeft
        case rotateRight
    }
}
