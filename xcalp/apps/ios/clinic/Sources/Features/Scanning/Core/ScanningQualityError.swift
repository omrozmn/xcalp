import Foundation

public enum ScanningQualityError: LocalizedError {
    case lowQuality(Float)
    case insufficientCoverage
    case excessiveMotion
    case poorLighting
    case qualityBelowThreshold
    
    public var errorDescription: String? {
        switch self {
        case .lowQuality(let score):
            return "Scan quality too low (Score: \(Int(score * 100))%). Try adjusting position or lighting."
        case .insufficientCoverage:
            return "Insufficient scan coverage. Please ensure complete coverage of the target area."
        case .excessiveMotion:
            return "Too much movement detected. Please hold the device more steady."
        case .poorLighting:
            return "Poor lighting conditions detected. Please ensure adequate lighting."
        case .qualityBelowThreshold:
            return "Scan quality below minimum threshold. Please try scanning again."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .lowQuality:
            return "Try moving closer to the subject or improving lighting conditions."
        case .insufficientCoverage:
            return "Move the device slowly around the subject to capture all angles."
        case .excessiveMotion:
            return "Hold the device steady and move more slowly."
        case .poorLighting:
            return "Ensure the area is well-lit and avoid strong shadows."
        case .qualityBelowThreshold:
            return "Try adjusting the distance, lighting, or scanning angle."
        }
    }
}