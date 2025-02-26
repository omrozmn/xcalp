import Foundation
import ARKit

public enum ScanningErrorType {
    case qualityLow(Float)
    case insufficientCoverage(Float)
    case motionBlur(Float)
    case systemResources
    case tracking
    case lighting
    case initialization
    case unknown
}

public struct ScanningError: Error {
    let type: ScanningErrorType
    let message: String
    let recommendation: String
    let canRetry: Bool
    let recoveryAction: (() -> Void)?
}

public class ScanningErrorHandler {
    private var retryCount = 0
    private let maxRetries = 3
    private var lastErrorTime: TimeInterval = 0
    private let errorCooldown: TimeInterval = 5.0
    
    public var onErrorOccurred: ((ScanningError) -> Void)?
    
    public func handleError(_ error: Error) -> ScanningError {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastErrorTime < errorCooldown {
            return createError(
                .unknown,
                message: "Too many errors",
                recommendation: "Please wait before retrying",
                canRetry: false
            )
        }
        
        lastErrorTime = currentTime
        
        if let arError = error as? ARError {
            return handleARError(arError)
        }
        
        switch error {
        case let qualityError as ScanningQualityError:
            return handleQualityError(qualityError)
        case let systemError as ScanningSystemError:
            return handleSystemError(systemError)
        default:
            return handleGenericError(error)
        }
    }
    
    private func handleARError(_ error: ARError) -> ScanningError {
        switch error.code {
        case .invalidReferenceImage:
            return createError(
                .initialization,
                message: "Failed to initialize scanning",
                recommendation: "Try moving to a different area with better lighting",
                canRetry: true
            )
        case .sensorUnavailable, .sensorFailed:
            return createError(
                .systemResources,
                message: "Camera sensor unavailable",
                recommendation: "Check camera permissions and restart the app",
                canRetry: false
            )
        case .worldTrackingFailed:
            return createError(
                .tracking,
                message: "Lost tracking position",
                recommendation: "Move device slowly and maintain visual features in view",
                canRetry: true
            )
        default:
            return createError(
                .unknown,
                message: "AR session error occurred",
                recommendation: "Try restarting the scanning process",
                canRetry: true
            )
        }
    }
    
    private func handleQualityError(_ error: ScanningQualityError) -> ScanningError {
        switch error {
        case .qualityBelowThreshold(let quality):
            return createError(
                .qualityLow(quality),
                message: "Scan quality too low",
                recommendation: "Move closer to the surface and ensure good lighting",
                canRetry: true
            )
        case .insufficientCoverage(let coverage):
            return createError(
                .insufficientCoverage(coverage),
                message: "Incomplete scan coverage",
                recommendation: "Continue scanning uncovered areas",
                canRetry: true
            )
        case .motionBlur(let amount):
            return createError(
                .motionBlur(amount),
                message: "Too much motion detected",
                recommendation: "Hold the device more steady",
                canRetry: true
            )
        }
    }
    
    private func handleSystemError(_ error: ScanningSystemError) -> ScanningError {
        switch error {
        case .insufficientMemory:
            return createError(
                .systemResources,
                message: "Not enough memory",
                recommendation: "Close other apps and try again",
                canRetry: true
            )
        case .deviceOverheating:
            return createError(
                .systemResources,
                message: "Device temperature too high",
                recommendation: "Let device cool down before continuing",
                canRetry: false
            )
        case .lowPower:
            return createError(
                .systemResources,
                message: "Low power mode active",
                recommendation: "Disable low power mode or charge device",
                canRetry: true
            )
        }
    }
    
    private func handleGenericError(_ error: Error) -> ScanningError {
        return createError(
            .unknown,
            message: "An unexpected error occurred",
            recommendation: "Try restarting the scanning process",
            canRetry: true
        )
    }
    
    private func createError(
        _ type: ScanningErrorType,
        message: String,
        recommendation: String,
        canRetry: Bool,
        recovery: (() -> Void)? = nil
    ) -> ScanningError {
        let error = ScanningError(
            type: type,
            message: message,
            recommendation: recommendation,
            canRetry: canRetry && retryCount < maxRetries,
            recoveryAction: recovery
        )
        
        onErrorOccurred?(error)
        
        if canRetry {
            retryCount += 1
        }
        
        return error
    }
    
    public func resetRetryCount() {
        retryCount = 0
    }
    
    public func canRetry() -> Bool {
        return retryCount < maxRetries
    }
}