public enum ProcessingError: Error {
    case processingFailed(Error)
    case storageError(Error)
    case networkError(Error)
    case queueLimitExceeded
    case operationTimeout
    case insufficientMemory(available: UInt64)
    case storageLimitExceeded(available: UInt64)
    case compressionFailed(String)
    case bufferCreationFailed
    case commandEncodingFailed
    case meshValidationFailed(String)
    case dataIntegrityError(String)
    
    public var errorDescription: String {
        switch self {
        case .processingFailed(let error):
            return "Processing failed: \(error.localizedDescription)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .queueLimitExceeded:
            return "Operation queue limit exceeded"
        case .operationTimeout:
            return "Operation timed out"
        case .insufficientMemory(let available):
            return "Insufficient memory. Available: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory))"
        case .storageLimitExceeded(let available):
            return "Storage limit exceeded. Available: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file))"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .bufferCreationFailed:
            return "Failed to create Metal buffers"
        case .commandEncodingFailed:
            return "Failed to encode Metal commands"
        case .meshValidationFailed(let reason):
            return "Mesh validation failed: \(reason)"
        case .dataIntegrityError(let reason):
            return "Data integrity check failed: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .insufficientMemory:
            return "Try closing other apps or processing a smaller scan"
        case .storageLimitExceeded:
            return "Free up storage space or try processing a smaller scan"
        case .queueLimitExceeded:
            return "Wait for current operations to complete"
        case .operationTimeout:
            return "Check system resources and try again"
        case .meshValidationFailed:
            return "Try capturing the scan again with better lighting and slower movement"
        default:
            return nil
        }
    }
}
