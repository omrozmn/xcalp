import Foundation

public enum ScanningError: LocalizedError {
    case deviceNotSupported
    case insufficientLighting
    case qualityBelowThreshold(current: Float, required: Float)
    case processingInProgress
    case invalidSession
    case invalidFrameData
    case noFallbackAvailable
    case unrecoverableError
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "This device does not support the required scanning features"
        case .insufficientLighting:
            return "The lighting conditions are too dark for accurate scanning"
        case .qualityBelowThreshold(let current, let required):
            return "Scan quality (current: \(current)) is below required threshold (\(required))"
        case .processingInProgress:
            return "A scanning process is already in progress"
        case .invalidSession:
            return "The scanning session is invalid or expired"
        case .invalidFrameData:
            return "Unable to process frame data"
        case .noFallbackAvailable:
            return "No fallback scanning mode is available"
        case .unrecoverableError:
            return "An unrecoverable error occurred during scanning"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotSupported:
            return "Try using a device with LiDAR scanner or supported camera system"
        case .insufficientLighting:
            return "Move to a better lit area or add more lighting"
        case .qualityBelowThreshold:
            return "Try scanning slower and ensure good lighting conditions"
        case .processingInProgress:
            return "Wait for the current scanning process to complete"
        case .invalidSession:
            return "Start a new scanning session"
        case .invalidFrameData:
            return "Try adjusting the scanning distance and angle"
        case .noFallbackAvailable:
            return "Try restarting the scanning process"
        case .unrecoverableError:
            return "Please restart the app and try again"
        }
    }
    
    public var recoveryOptions: [String] {
        switch self {
        case .deviceNotSupported:
            return ["Switch to Photo Mode", "Cancel"]
        case .insufficientLighting:
            return ["Enable Flash", "Continue Anyway", "Cancel"]
        case .qualityBelowThreshold:
            return ["Adjust Settings", "Continue Anyway", "Cancel"]
        case .processingInProgress:
            return ["Wait", "Cancel Processing"]
        case .invalidSession:
            return ["Start New Session", "Cancel"]
        case .invalidFrameData:
            return ["Try Again", "Switch Mode", "Cancel"]
        case .noFallbackAvailable:
            return ["Restart", "Cancel"]
        case .unrecoverableError:
            return ["Restart App"]
        }
    }
    
    public var isRecoverable: Bool {
        switch self {
        case .unrecoverableError:
            return false
        default:
            return true
        }
    }
    
    public var requiresUserIntervention: Bool {
        switch self {
        case .insufficientLighting, .qualityBelowThreshold:
            return true
        default:
            return false
        }
    }
    
    public var suggestedDelay: TimeInterval {
        switch self {
        case .processingInProgress:
            return 2.0
        case .insufficientLighting:
            return 1.0
        case .qualityBelowThreshold:
            return 0.5
        default:
            return 0.0
        }
    }
    
    public var shouldLog: Bool {
        switch self {
        case .qualityBelowThreshold, .insufficientLighting:
            return false // These are common and expected
        default:
            return true
        }
    }
}

public protocol ScanningErrorHandler: AnyObject {
    func handle(_ error: ScanningError) async
    func recover(from error: ScanningError) async throws
    func getFallbackMode(for error: ScanningError) -> ScanningMode?
}

public extension ScanningErrorHandler {
    func handle(_ error: ScanningError) async {
        if error.shouldLog {
            os_log(
                .error,
                "Scanning error occurred: %{public}@",
                error.localizedDescription
            )
        }
        
        if error.isRecoverable {
            do {
                try await recover(from: error)
            } catch {
                os_log(
                    .error,
                    "Error recovery failed: %{public}@",
                    error.localizedDescription
                )
            }
        }
        
        if error.requiresUserIntervention {
            NotificationCenter.default.post(
                name: .scanningErrorRequiresIntervention,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }
    
    func recover(from error: ScanningError) async throws {
        switch error {
        case .insufficientLighting:
            try await adjustLightingSettings()
        case .qualityBelowThreshold:
            try await adjustQualitySettings()
        case .invalidFrameData:
            try await resetFrameProcessing()
        case .invalidSession:
            try await resetSession()
        case .processingInProgress:
            try await Task.sleep(nanoseconds: UInt64(error.suggestedDelay * 1_000_000_000))
        case .deviceNotSupported:
            if let fallbackMode = getFallbackMode(for: error) {
                try await switchToMode(fallbackMode)
            }
        default:
            throw error
        }
    }
    
    private func adjustLightingSettings() async throws {
        // Implement lighting adjustment logic
    }
    
    private func adjustQualitySettings() async throws {
        // Implement quality adjustment logic
    }
    
    private func resetFrameProcessing() async throws {
        // Implement frame processing reset logic
    }
    
    private func resetSession() async throws {
        // Implement session reset logic
    }
    
    private func switchToMode(_ mode: ScanningMode) async throws {
        // Implement mode switching logic
    }
}

extension Notification.Name {
    public static let scanningErrorRequiresIntervention = Notification.Name("scanningErrorRequiresIntervention")
}