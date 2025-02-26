import Foundation

public class CaptureProgressManager {
    public enum CaptureStage {
        case preparingCapture
        case processingDepthData
        case generatingMesh
        case optimizingMesh
        case preparingExport
        case complete
        
        public var progress: Float {
            switch self {
            case .preparingCapture: return 0.0
            case .processingDepthData: return 0.2
            case .generatingMesh: return 0.4
            case .optimizingMesh: return 0.6
            case .preparingExport: return 0.8
            case .complete: return 1.0
            }
        }
        
        public var description: String {
            switch self {
            case .preparingCapture: return "Preparing capture..."
            case .processingDepthData: return "Processing depth data..."
            case .generatingMesh: return "Generating 3D mesh..."
            case .optimizingMesh: return "Optimizing mesh..."
            case .preparingExport: return "Preparing for export..."
            case .complete: return "Capture complete"
            }
        }
    }
    
    private var progressHandler: ((CaptureStage) -> Void)?
    private var stage: CaptureStage = .preparingCapture {
        didSet {
            progressHandler?(stage)
        }
    }
    
    public func setProgressHandler(_ handler: @escaping (CaptureStage) -> Void) {
        self.progressHandler = handler
    }
    
    public func updateStage(_ newStage: CaptureStage) {
        stage = newStage
    }
    
    public func reset() {
        stage = .preparingCapture
    }
}