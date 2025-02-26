import UIKit
import AVFoundation

public class AccessibilityManager {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastAnnouncementTime: TimeInterval = 0
    private let announcementCooldown: TimeInterval = 2.0
    
    private var isVoiceOverRunning: Bool {
        return UIAccessibility.isVoiceOverRunning
    }
    
    public func setupAccessibility(
        for scanView: UIView,
        qualityHandler: @escaping (Float) -> Void,
        guidanceHandler: @escaping (String) -> Void
    ) {
        // Configure accessibility for the scanning view
        scanView.isAccessibilityElement = true
        scanView.accessibilityLabel = "Scanning View"
        scanView.accessibilityHint = "Shows the camera feed and scanning progress"
        
        // Add accessibility actions
        scanView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Check Scanning Quality",
                target: self,
                selector: #selector(handleQualityCheck)
            ),
            UIAccessibilityCustomAction(
                name: "Get Guidance",
                target: self,
                selector: #selector(handleGuidanceRequest)
            )
        ]
        
        // Set handlers
        self.qualityCheckHandler = qualityHandler
        self.guidanceRequestHandler = guidanceHandler
    }
    
    public func announceQuality(_ quality: Float) {
        guard shouldAnnounce() else { return }
        
        let message: String
        switch quality {
        case 0..<0.3:
            message = "Scanning quality is poor. Move closer to the surface."
        case 0.3..<0.7:
            message = "Scanning quality is fair. Continue scanning slowly."
        default:
            message = "Scanning quality is good. Maintain current position."
        }
        
        announce(message)
    }
    
    public func announceGuidance(_ guidance: String) {
        guard shouldAnnounce() else { return }
        announce(guidance)
    }
    
    public func announceProgress(_ progress: Float) {
        guard shouldAnnounce(),
              progress.truncatingRemainder(dividingBy: 0.25) < 0.01 else {
            return
        }
        
        let percentage = Int(progress * 100)
        announce("Scan progress: \(percentage) percent complete")
    }
    
    public func announceError(_ error: ScanningError) {
        announce("\(error.message). \(error.recommendation)")
    }
    
    public func getAccessibleDescription(for metrics: ScanningMetrics) -> String {
        var description = "Performance Status: "
        
        if metrics.isPerformanceAcceptable {
            description += "Optimal. "
        } else {
            description += "Needs attention. "
        }
        
        description += "Frame rate: \(Int(metrics.fps)) frames per second. "
        description += "Memory usage: \(Int(metrics.memoryUsage * 100)) percent. "
        description += "Battery level: \(Int(metrics.batteryLevel * 100)) percent."
        
        return description
    }
    
    private func shouldAnnounce() -> Bool {
        guard isVoiceOverRunning else { return false }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastAnnouncementTime >= announcementCooldown else {
            return false
        }
        
        lastAnnouncementTime = currentTime
        return true
    }
    
    private func announce(_ message: String) {
        if isVoiceOverRunning {
            // Use VoiceOver announcement
            UIAccessibility.post(
                notification: .announcement,
                argument: message
            )
        } else {
            // Use speech synthesis
            let utterance = AVSpeechUtterance(string: message)
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            synthesizer.speak(utterance)
        }
    }
    
    // Dynamic Type support
    public func scaledFont(for textStyle: UIFont.TextStyle, baseSize: CGFloat) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        let font = UIFont.systemFont(ofSize: baseSize)
        return metrics.scaledFont(for: font)
    }
    
    // High contrast support
    public func highContrastColor(for color: UIColor) -> UIColor {
        if UIAccessibility.isDarkerSystemColorsEnabled {
            return color.adjustedForDarkerSystem()
        }
        return color
    }
    
    // Handlers for accessibility actions
    private var qualityCheckHandler: ((Float) -> Void)?
    private var guidanceRequestHandler: ((String) -> Void)?
    
    @objc private func handleQualityCheck() {
        qualityCheckHandler?(0)
    }
    
    @objc private func handleGuidanceRequest() {
        guidanceRequestHandler?("")
    }
}

private extension UIColor {
    func adjustedForDarkerSystem() -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Increase contrast by adjusting brightness
        if brightness > 0.5 {
            brightness = min(brightness * 1.3, 1.0)
        } else {
            brightness = max(brightness * 0.7, 0.0)
        }
        
        return UIColor(
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
    }
}