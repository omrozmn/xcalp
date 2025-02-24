import Foundation
import Combine
import SwiftUI
import os.log

public final class ScanningFeedbackService: ObservableObject {
    @Published public private(set) var qualityStatus: ScanQualityStatus = .unknown
    @Published public private(set) var processingStatus: ProcessingStatus = .idle
    @Published public private(set) var guidanceMessages: [GuidanceMessage] = []
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningFeedback")
    private var qualityThresholds: QualityThresholds
    
    public init(qualityThresholds: QualityThresholds = QualityThresholds()) {
        self.qualityThresholds = qualityThresholds
        setupNotificationHandling()
    }
    
    public func updateQualityMetrics(_ metrics: [String: Float]) {
        let status = evaluateQualityStatus(metrics)
        
        DispatchQueue.main.async {
            self.qualityStatus = status
            self.updateGuidance(for: status, metrics: metrics)
        }
    }
    
    public func updateProcessingStatus(_ status: ProcessingStatus) {
        DispatchQueue.main.async {
            self.processingStatus = status
            
            if case .error(let message) = status {
                self.addGuidanceMessage(.error(message))
            }
        }
    }
    
    private func evaluateQualityStatus(_ metrics: [String: Float]) -> ScanQualityStatus {
        guard let lidarQuality = metrics["lidar_quality"],
              let photoQuality = metrics["photo_quality"],
              let pointDensity = metrics["point_density"] else {
            return .unknown
        }
        
        if lidarQuality < qualityThresholds.minLidarQuality ||
           photoQuality < qualityThresholds.minPhotoQuality {
            return .poor
        }
        
        if pointDensity < qualityThresholds.minPointDensity {
            return .insufficient
        }
        
        if lidarQuality > qualityThresholds.optimalLidarQuality &&
           photoQuality > qualityThresholds.optimalPhotoQuality {
            return .excellent
        }
        
        return .good
    }
    
    private func updateGuidance(for status: ScanQualityStatus, metrics: [String: Float]) {
        guidanceMessages.removeAll(where: { $0.isExpired })
        
        switch status {
        case .poor:
            if let lidarQuality = metrics["lidar_quality"],
               lidarQuality < qualityThresholds.minLidarQuality {
                addGuidanceMessage(.qualityWarning("Move device closer to surface"))
            }
            if let motionScore = metrics["motion_score"],
               motionScore < qualityThresholds.minMotionScore {
                addGuidanceMessage(.qualityWarning("Hold device more steady"))
            }
            
        case .insufficient:
            addGuidanceMessage(.qualityWarning("Scan more areas to improve coverage"))
            
        case .good, .excellent:
            if guidanceMessages.contains(where: { $0.type == .qualityWarning }) {
                guidanceMessages.removeAll(where: { $0.type == .qualityWarning })
                addGuidanceMessage(.success("Scan quality is good"))
            }
            
        case .unknown:
            addGuidanceMessage(.info("Initializing scanning..."))
        }
    }
    
    private func addGuidanceMessage(_ message: GuidanceMessage) {
        DispatchQueue.main.async {
            self.guidanceMessages.append(message)
            
            // Remove message after its duration
            DispatchQueue.main.asyncAfter(deadline: .now() + message.duration) {
                self.guidanceMessages.removeAll(where: { $0.id == message.id })
            }
        }
    }
    
    private func setupNotificationHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScanningModeChange(_:)),
            name: Notification.Name("ScanningModeChanged"),
            object: nil
        )
    }
    
    @objc private func handleScanningModeChange(_ notification: Notification) {
        if let mode = notification.userInfo?["mode"] as? ScanningModes {
            addGuidanceMessage(.info("Switched to \(mode.displayName) scanning mode"))
        }
    }
}

public enum ScanQualityStatus {
    case unknown
    case poor
    case insufficient
    case good
    case excellent
}

public enum ProcessingStatus {
    case idle
    case processing(progress: Float)
    case error(String)
}

public struct GuidanceMessage: Identifiable {
    public let id = UUID()
    public let type: MessageType
    public let text: String
    public let duration: TimeInterval
    public let timestamp = Date()
    
    public enum MessageType {
        case info
        case success
        case qualityWarning
        case error
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > duration
    }
    
    static func info(_ text: String) -> GuidanceMessage {
        GuidanceMessage(type: .info, text: text, duration: 3.0)
    }
    
    static func success(_ text: String) -> GuidanceMessage {
        GuidanceMessage(type: .success, text: text, duration: 2.0)
    }
    
    static func qualityWarning(_ text: String) -> GuidanceMessage {
        GuidanceMessage(type: .qualityWarning, text: text, duration: 4.0)
    }
    
    static func error(_ text: String) -> GuidanceMessage {
        GuidanceMessage(type: .error, text: text, duration: 5.0)
    }
}

public struct QualityThresholds {
    let minLidarQuality: Float = 0.7
    let minPhotoQuality: Float = 0.6
    let optimalLidarQuality: Float = 0.9
    let optimalPhotoQuality: Float = 0.85
    let minPointDensity: Float = 500
    let minMotionScore: Float = 0.8
}