import Foundation
import os.log

extension MeshProcessor {
    struct ErrorContext {
        let operation: String
        let details: String
        let severity: ErrorSeverity
        let metrics: ProcessingMetrics?
        let recoveryOptions: [RecoveryOption]
    }
    
    enum ErrorSeverity {
        case warning
        case error
        case critical
    }
    
    enum RecoveryOption {
        case retryOperation
        case reduceMeshQuality
        case skipPhotogrammetry
        case useAlternativeAlgorithm
        case abortProcessing
    }
    
    func handleError(_ error: Error, context: ErrorContext) -> RecoveryOption {
        logger.error("""
            Processing error: \(error.localizedDescription)
            Operation: \(context.operation)
            Details: \(context.details)
            Severity: \(context.severity)
            """)
        
        // Log performance metrics if available
        if let metrics = context.metrics {
            logger.error("""
                Performance at error:
                Memory: \(ByteCountFormatter.string(fromByteCount: metrics.memoryUsage, countStyle: .memory))
                GPU Usage: \(String(format: "%.1f%%", metrics.gpuUsage * 100))
                Processing Time: \(String(format: "%.2fs", metrics.processingDuration))
                """)
        }
        
        // Determine best recovery option based on context
        switch context.severity {
        case .warning:
            return handleWarning(context)
        case .error:
            return handleError(context)
        case .critical:
            return handleCritical(context)
        }
    }
    
    private func handleWarning(_ context: ErrorContext) -> RecoveryOption {
        // For warnings, try to continue with reduced quality
        if context.operation.contains("photogrammetry") {
            return .skipPhotogrammetry
        }
        return .reduceMeshQuality
    }
    
    private func handleError(_ context: ErrorContext) -> RecoveryOption {
        // For errors, try alternative approaches
        if context.metrics?.memoryUsage ?? 0 > 500_000_000 { // 500MB
            return .reduceMeshQuality
        }
        
        if context.operation.contains("GPU") {
            return .useAlternativeAlgorithm
        }
        
        return .retryOperation
    }
    
    private func handleCritical(_ context: ErrorContext) -> RecoveryOption {
        // For critical errors, abort processing
        return .abortProcessing
    }
    
    func applyRecoveryOption(_ option: RecoveryOption, quality: inout MeshQuality) {
        switch option {
        case .retryOperation:
            // Add delay before retry
            Thread.sleep(forTimeInterval: 0.5)
            
        case .reduceMeshQuality:
            // Step down quality level
            switch quality {
            case .high:
                quality = .medium
            case .medium:
                quality = .low
            case .low:
                break
            }
            
        case .skipPhotogrammetry:
            // Continue with LiDAR only
            logger.info("Continuing with LiDAR-only processing")
            
        case .useAlternativeAlgorithm:
            // Switch to CPU processing
            logger.info("Switching to CPU processing pipeline")
            
        case .abortProcessing:
            logger.critical("Processing aborted due to unrecoverable error")
        }
    }
}

// Convenience initializers for error context
extension MeshProcessor.ErrorContext {
    static func gpuError(
        details: String,
        metrics: ProcessingMetrics? = nil
    ) -> MeshProcessor.ErrorContext {
        MeshProcessor.ErrorContext(
            operation: "GPU Processing",
            details: details,
            severity: .error,
            metrics: metrics,
            recoveryOptions: [.useAlternativeAlgorithm, .reduceMeshQuality, .abortProcessing]
        )
    }
    
    static func qualityError(
        details: String,
        metrics: ProcessingMetrics? = nil
    ) -> MeshProcessor.ErrorContext {
        MeshProcessor.ErrorContext(
            operation: "Quality Validation",
            details: details,
            severity: .warning,
            metrics: metrics,
            recoveryOptions: [.reduceMeshQuality, .skipPhotogrammetry, .abortProcessing]
        )
    }
    
    static func memoryError(
        details: String,
        metrics: ProcessingMetrics? = nil
    ) -> MeshProcessor.ErrorContext {
        MeshProcessor.ErrorContext(
            operation: "Memory Management",
            details: details,
            severity: .critical,
            metrics: metrics,
            recoveryOptions: [.reduceMeshQuality, .abortProcessing]
        )
    }
}