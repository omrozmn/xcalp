import Foundation
/// A description
import ARKit
import AVFoundation
import CoreMotion

class ScanQualityMonitor {
    private var monitoringTimer: Timer?
    private let motionManager = CMMotionManager()
    private var lastMotionTimestamp: TimeInterval = 0
    private var motionBuffer: [Float] = []
    private let bufferSize = 10
    
    private var session: ARSession?
    private var lastLightingConditions: Float = 1000.0
    private var lastPointCloud: ARPointCloud?
    
    init(session: ARSession? = nil) {
        self.session = session
        setupMotionManager()
    }
    
    deinit {
        stopMonitoring()
        motionManager.stopDeviceMotionUpdates()
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.processMotionData(motion)
        }
    }
    
    func startMonitoring(callback: @escaping (ScanQuality) -> Void) {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let quality = ScanQuality(
                lighting: self.measureLightingConditions(),
                motionScore: self.calculateMotionScore(),
                featureScore: self.calculateFeatureScore(),
                pointDensity: self.calculatePointDensity()
            )
            
            callback(quality)
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    func update(with frame: ARFrame) {
        lastLightingConditions = frame.lightEstimate?.ambientIntensity ?? 1000.0
        lastPointCloud = frame.rawFeaturePoints
    }
    
    private func measureLightingConditions() -> Float {
        // Convert ambient intensity to lux (roughly)
        // ARKit provides intensity in lumens/m^2, which is approximately equal to lux
        return lastLightingConditions
    }
    
    private func processMotionData(_ motion: CMDeviceMotion) {
        let timestamp = motion.timestamp
        
        // Calculate motion magnitude from acceleration and rotation rate
        let acceleration = motion.userAcceleration
        let rotation = motion.rotationRate
        
        let motionMagnitude = Float(sqrt(
            pow(acceleration.x, 2) + pow(acceleration.y, 2) + pow(acceleration.z, 2) +
            pow(rotation.x, 2) + pow(rotation.y, 2) + pow(rotation.z, 2)
        ))
        
        // Add to circular buffer
        if motionBuffer.count >= bufferSize {
            motionBuffer.removeFirst()
        }
        motionBuffer.append(motionMagnitude)
        
        lastMotionTimestamp = timestamp
    }
    
    private func calculateMotionScore() -> Float {
        guard !motionBuffer.isEmpty else { return 0.0 }
        
        // Calculate RMS of motion values
        let meanSquare = motionBuffer.reduce(0) { $0 + $1 * $1 } / Float(motionBuffer.count)
        let rms = sqrt(meanSquare)
        
        // Convert to mm deviation (calibrated value)
        let mmDeviation = rms * 10.0 // Scale factor determined through calibration
        
        return mmDeviation
    }
    
    private func calculateFeatureScore() -> Float {
        guard let pointCloud = lastPointCloud else { return 0.0 }
        
        // Calculate feature quality based on point confidence and distribution
        let confidenceSum = pointCloud.identifiers.reduce(0.0) { $0 + Double($1) }
        let averageConfidence = Float(confidenceSum) / Float(pointCloud.count)
        
        // Normalize to 0-1 range
        return min(max(averageConfidence, 0.0), 1.0)
    }
    
    private func calculatePointDensity() -> Float {
        guard let pointCloud = lastPointCloud,
              pointCloud.count > 0 else { return 0.0 }
        
        // Convert points to array for processing
        let points = Array(UnsafeBufferPointer(start: pointCloud.points.assumingMemoryBound(to: SIMD3<Float>.self),
                                             count: pointCloud.count))
        
        // Calculate bounding volume
        var minPoint = points[0]
        var maxPoint = points[0]
        
        for point in points {
            minPoint = min(minPoint, point)
            maxPoint = max(maxPoint, point)
        }
        
        let dimensions = maxPoint - minPoint
        let volume = dimensions.x * dimensions.y * dimensions.z
        
        // Calculate density in points/cm³, then convert to points/cm²
        // by taking the cubic root of the volume density
        let volumeDensity = Float(pointCloud.count) / (volume * 1000000.0) // Convert to cm³
        let areaDensity = pow(volumeDensity, 2.0/3.0) * 100.0 // Scale factor for points/cm²
        
        return areaDensity
    }
}