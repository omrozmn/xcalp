import Foundation

public enum ScanningError: LocalizedError {
    case deviceNotSupported
    case initialization(underlyingError: Error)
    case processingFailed(reason: String)
    case qualityCheckFailed
    case meshValidationFailed(issues: [MeshIssue])
    case insufficientMemory
    case thermalThrottling
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "This device does not support LiDAR scanning"
        case .initialization(let error):
            return "Failed to initialize scanning: \(error.localizedDescription)"
        case .processingFailed(let reason):
            return "Mesh processing failed: \(reason)"
        case .qualityCheckFailed:
            return "Scan quality check failed"
        case .meshValidationFailed(let issues):
            return "Mesh validation failed: \(issues.map(\.description).joined(separator: ", "))"
        case .insufficientMemory:
            return "Not enough memory available for processing"
        case .thermalThrottling:
            return "Device temperature too high for processing"
        case .timeout:
            return "Operation timed out"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotSupported:
            return "Please use a device with LiDAR sensor"
        case .initialization:
            return "Try restarting the app"
        case .processingFailed:
            return "Try scanning again"
        case .qualityCheckFailed:
            return "Ensure good lighting and steady movement"
        case .meshValidationFailed:
            return "Try scanning from a different angle"
        case .insufficientMemory:
            return "Close other apps and try again"
        case .thermalThrottling:
            return "Let the device cool down and try again"
        case .timeout:
            return "Check your internet connection and try again"
        }
    }
}

public enum MeshIssue: CustomStringConvertible {
    case tooFewVertices(count: Int, minimum: Int)
    case tooManyHoles(count: Int)
    case poorVertexDensity(density: Float, minimum: Float)
    case inconsistentNormals(consistency: Float, minimum: Float)
    
    public var description: String {
        switch self {
        case .tooFewVertices(let count, let minimum):
            return "Too few vertices: \(count) < \(minimum)"
        case .tooManyHoles(let count):
            return "Too many holes detected: \(count)"
        case .poorVertexDensity(let density, let minimum):
            return "Low vertex density: \(density) < \(minimum)"
        case .inconsistentNormals(let consistency, let minimum):
            return "Poor normal consistency: \(consistency) < \(minimum)"
        }
    }
}
