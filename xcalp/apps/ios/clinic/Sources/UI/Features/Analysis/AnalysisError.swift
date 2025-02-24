import CoreML
import Foundation
import Vision

public enum AnalysisError: LocalizedError {
    case modelInitializationFailed
    case invalidData(String)
    case processingError(String)
    case resourceExhausted
    case modelExecutionFailed(String)
    case qualityInsufficient(String)
    case outOfBounds(String)
    
    public var errorDescription: String? {
        switch self {
        case .modelInitializationFailed:
            return "Failed to initialize analysis model"
        case .invalidData(let details):
            return "Invalid analysis data: \(details)"
        case .processingError(let details):
            return "Processing error: \(details)"
        case .resourceExhausted:
            return "Insufficient resources to complete analysis"
        case .modelExecutionFailed(let details):
            return "Model execution failed: \(details)"
        case .qualityInsufficient(let details):
            return "Quality check failed: \(details)"
        case .outOfBounds(let details):
            return "Value out of acceptable range: \(details)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .modelInitializationFailed:
            return "Please restart the app and try again"
        case .invalidData:
            return "Please ensure scan data is valid and try again"
        case .processingError:
            return "Please check scan quality and try again"
        case .resourceExhausted:
            return "Please close other apps and try again"
        case .modelExecutionFailed:
            return "Please ensure device meets minimum requirements"
        case .qualityInsufficient:
            return "Please perform a new scan with better quality"
        case .outOfBounds:
            return "Please adjust analysis parameters within valid ranges"
        }
    }
}

extension AnalysisFeature {
    func handleError(_ error: Error) {
        let analytics = AnalyticsService.shared
        let logger = Logger(subsystem: "com.xcalp.clinic", category: "analysis")
        
        // Determine severity
        let severity: ErrorSeverity = {
            switch error {
            case AnalysisError.modelInitializationFailed,
                 AnalysisError.resourceExhausted,
                 AnalysisError.modelExecutionFailed:
                return .critical
            case AnalysisError.invalidData,
                 AnalysisError.processingError:
                return .error
            case AnalysisError.qualityInsufficient,
                 AnalysisError.outOfBounds:
                return .warning
            default:
                return .error
            }
        }()
        
        // Log error with context
        analytics.logError(error, severity: severity, context: [
            "feature": "analysis",
            "analysisType": selectedAnalysisType?.rawValue ?? "unknown",
            "deviceModel": UIDevice.current.modelName,
            "memoryAvailable": ProcessInfo.processInfo.physicalMemory
        ])
        
        // Log to system
        logger.error("Analysis error: \(error.localizedDescription)")
        
        // Attempt recovery
        if let analysisError = error as? AnalysisError {
            switch analysisError {
            case .resourceExhausted:
                PerformanceOptimizer.shared.cleanupResources()
            case .modelExecutionFailed:
                MLModelManager.shared.resetModel()
            case .qualityInsufficient:
                VoiceGuidanceManager.shared.provideGuidance(for: .qualityWarning)
            default:
                break
            }
        }
        
        // Update state with user-friendly message
        self.errorMessage = error.localizedDescription
    }
}

// MARK: - Performance Optimization
private final class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()
    private let monitor = PerformanceMonitor.shared
    
    func cleanupResources() {
        // Clear image caches
        URLCache.shared.removeAllCachedResponses()
        
        // Clear temporary files
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory)
        
        // Reset ML context
        MLModelManager.shared.resetContext()
    }
}

// MARK: - ML Model Management
private final class MLModelManager {
    static let shared = MLModelManager()
    private var context: MLContext?
    
    func resetModel() {
        context = nil
        try? MLModel.compileModel(at: modelURL)
    }
    
    func resetContext() {
        context = MLContext()
    }
}
