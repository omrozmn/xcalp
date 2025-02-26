import Foundation
import RealityKit

public class ScanningCacheManager {
    private let cacheQueue = DispatchQueue(label: "com.xcalp.scanningCache")
    private let maxCacheSize = 100_000 // Maximum number of points to cache
    private let checkpointInterval = 1000 // Save checkpoint every 1000 points
    
    private var cachedPoints: [Point3D] = []
    private var checkpoints: [Int: [Point3D]] = [:] // Points at each checkpoint
    private var qualityHistory: [Float] = []
    
    public func cachePoints(_ points: [Point3D], quality: Float) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.cachedPoints.append(contentsOf: points)
            self.qualityHistory.append(quality)
            
            // Create checkpoint if needed
            if self.cachedPoints.count >= self.checkpoints.count * self.checkpointInterval {
                self.createCheckpoint()
            }
            
            // Trim cache if it exceeds maximum size
            self.trimCacheIfNeeded()
        }
    }
    
    private func createCheckpoint() {
        let checkpointIndex = checkpoints.count
        checkpoints[checkpointIndex] = Array(cachedPoints)
    }
    
    private func trimCacheIfNeeded() {
        if cachedPoints.count > maxCacheSize {
            // Keep the most recent points
            cachedPoints = Array(cachedPoints.suffix(maxCacheSize))
            
            // Update checkpoints
            let remainingCheckpoints = checkpoints.filter { $0.key >= checkpoints.count - 5 }
            checkpoints = remainingCheckpoints
        }
    }
    
    public func restoreFromLastCheckpoint() -> (points: [Point3D], quality: Float)? {
        guard let lastCheckpointIndex = checkpoints.keys.max(),
              let lastCheckpoint = checkpoints[lastCheckpointIndex],
              !qualityHistory.isEmpty else {
            return nil
        }
        
        // Calculate average quality for the checkpoint
        let averageQuality = qualityHistory.reduce(0, +) / Float(qualityHistory.count)
        
        return (lastCheckpoint, averageQuality)
    }
    
    public func getCachedPoints() -> [Point3D] {
        var points: [Point3D] = []
        cacheQueue.sync {
            points = cachedPoints
        }
        return points
    }
    
    public func getAverageQuality() -> Float {
        var quality: Float = 0
        cacheQueue.sync {
            quality = qualityHistory.reduce(0, +) / Float(max(1, qualityHistory.count))
        }
        return quality
    }
    
    public func clear() {
        cacheQueue.async { [weak self] in
            self?.cachedPoints.removeAll()
            self?.checkpoints.removeAll()
            self?.qualityHistory.removeAll()
        }
    }
    
    public var pointCount: Int {
        var count = 0
        cacheQueue.sync {
            count = cachedPoints.count
        }
        return count
    }
    
    public func hasSufficientData() -> Bool {
        return pointCount >= checkpointInterval
    }
}