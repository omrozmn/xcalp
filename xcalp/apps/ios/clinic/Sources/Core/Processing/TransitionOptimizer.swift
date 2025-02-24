import Foundation
import simd

class TransitionOptimizer {
    private let bufferSize = 30 // Number of frames to buffer during transition
    private var pointBuffer: [ScanFrame] = []
    private let qualityCalculator = QualityMetricsCalculator()
    
    func bufferFrame(_ frame: ScanFrame) {
        pointBuffer.append(frame)
        if pointBuffer.count > bufferSize {
            pointBuffer.removeFirst()
        }
    }
    
    func optimizeTransition(from oldMode: ScanningModes, to newMode: ScanningModes) -> [SIMD3<Float>] {
        // Sort frames by quality
        let sortedFrames = pointBuffer.sorted { $0.quality > $1.quality }
        
        // Select best frames based on transition type
        let selectedFrames = selectOptimalFrames(
            frames: sortedFrames,
            oldMode: oldMode,
            newMode: newMode
        )
        
        // Merge points from selected frames
        return mergeFrames(selectedFrames)
    }
    
    private func selectOptimalFrames(frames: [ScanFrame], oldMode: ScanningModes, newMode: ScanningModes) -> [ScanFrame] {
        switch (oldMode, newMode) {
        case (.lidarOnly, .photogrammetryOnly):
            return selectFramesForLidarToPhoto(frames)
        case (.photogrammetryOnly, .lidarOnly):
            return selectFramesForPhotoToLidar(frames)
        case (_, .hybridFusion):
            return selectFramesForFusion(frames)
        default:
            return Array(frames.prefix(5)) // Default to best 5 frames
        }
    }
    
    private func selectFramesForLidarToPhoto(_ frames: [ScanFrame]) -> [ScanFrame] {
        // Prioritize frames with good feature matching
        frames.filter { frame in
            frame.photoQuality > ScanningQualityThresholds.minimumPhotogrammetryConfidence
        }
    }
    
    private func selectFramesForPhotoToLidar(_ frames: [ScanFrame]) -> [ScanFrame] {
        // Prioritize frames with good depth consistency
        frames.filter { frame in
            frame.lidarQuality > ScanningQualityThresholds.minimumLidarConfidence
        }
    }
    
    private func selectFramesForFusion(_ frames: [ScanFrame]) -> [ScanFrame] {
        // Select frames with good quality in both modalities
        frames.filter { frame in
            frame.lidarQuality > ScanningQualityThresholds.minimumLidarConfidence &&
            frame.photoQuality > ScanningQualityThresholds.minimumPhotogrammetryConfidence
        }
    }
    
    private func mergeFrames(_ frames: [ScanFrame]) -> [SIMD3<Float>] {
        var mergedPoints: Set<SIMD3<Float>> = []
        let kdTree = KDTree(points: [])
        
        for frame in frames {
            for point in frame.points {
                // Check if similar point already exists
                if let nearest = kdTree.nearest(to: point) {
                    let distance = length(point - nearest)
                    if distance > ScanningQualityThresholds.maximumFusionDistance {
                        mergedPoints.insert(point)
                    }
                } else {
                    mergedPoints.insert(point)
                }
            }
        }
        
        return Array(mergedPoints)
    }
}

struct ScanFrame {
    let points: [SIMD3<Float>]
    let lidarQuality: Float
    let photoQuality: Float
    let timestamp: Date
    
    var quality: Float {
        (lidarQuality + photoQuality) / 2.0
    }
}
