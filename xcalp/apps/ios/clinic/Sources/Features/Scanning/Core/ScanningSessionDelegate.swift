import AVFoundation
import Combine
import CoreImage
import RealityKit

class ScanningSessionDelegate: NSObject {
    private let depthProcessor = DepthDataProcessor()
    private let qualityThreshold: Float = 0.7
    private var consecutiveLowQualityFrames = 0
    private let maxLowQualityFrames = 30
    
    private var onQualityUpdate: ((Float) -> Void)?
    private var onGuidanceUpdate: ((String) -> Void)?
    private var onFailure: ((Error) -> Void)?
    
    // Quality monitoring
    private var depthQualityHistory: [Float] = []
    private let maxHistorySize = 10
    
    init(
        onQualityUpdate: ((Float) -> Void)? = nil,
        onGuidanceUpdate: ((String) -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) {
        self.onQualityUpdate = onQualityUpdate
        self.onGuidanceUpdate = onGuidanceUpdate
        self.onFailure = onFailure
        super.init()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        onFailure?(error)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        processFrame(frame)
    }
    
    private func processFrame(_ frame: ARFrame) {
        if let depthMap = frame.sceneDepth?.depthMap {
            // LiDAR frame
            let result = depthProcessor.processDepthData(depthMap, source: .lidar)
            updateQualityMetrics(result)
            provideLiDARGuidance(result: result, frame: frame)
        } else if let depthData = frame.capturedDepthData?.depthDataMap {
            // TrueDepth frame
            let result = depthProcessor.processDepthData(depthData, source: .trueDepth)
            updateQualityMetrics(result)
            provideTrueDepthGuidance(result: result, frame: frame)
        }
    }
    
    private func updateQualityMetrics(_ result: DepthProcessingResult) {
        depthQualityHistory.append(result.quality)
        if depthQualityHistory.count > maxHistorySize {
            depthQualityHistory.removeFirst()
        }
        
        let averageQuality = depthQualityHistory.reduce(0, +) / Float(depthQualityHistory.count)
        onQualityUpdate?(averageQuality)
        
        if averageQuality < qualityThreshold {
            consecutiveLowQualityFrames += 1
            if consecutiveLowQualityFrames >= maxLowQualityFrames {
                onFailure?(ScanningQualityError.qualityBelowThreshold)
            }
        } else {
            consecutiveLowQualityFrames = 0
        }
    }
    
    private func provideLiDARGuidance(result: DepthProcessingResult, frame: ARFrame) {
        var guidance = ""
        
        if result.coverage < 0.5 {
            guidance = "Move the device to cover more area"
        } else if result.quality < 0.3 {
            guidance = "Move closer to the surface"
        } else if result.quality < 0.7 {
            if frame.camera.trackingState != .normal {
                guidance = "Hold the device more steady"
            } else {
                guidance = "Slowly scan the entire surface"
            }
        }
        
        onGuidanceUpdate?(guidance)
    }
    
    private func provideTrueDepthGuidance(result: DepthProcessingResult, frame: ARFrame) {
        var guidance = ""
        
        if result.coverage < 0.5 {
            guidance = "Keep your face centered in the frame"
        } else if result.quality < 0.3 {
            guidance = "Move slightly closer to the camera"
        } else if result.quality < 0.7 {
            if frame.camera.trackingState != .normal {
                guidance = "Hold your head steady"
            } else {
                guidance = "Slowly turn your head side to side"
            }
        }
        
        onGuidanceUpdate?(guidance)
    }
}