import Foundation
import CoreMotion
import ARKit

public class AdaptiveScanningSpeedController {
    private let motionManager = CMMotionManager()
    private var optimalSpeed: Float = 0.5 // meters per second
    private var speedHistory: [Float] = []
    private let historySize = 30
    private var lastUpdateTime: TimeInterval = 0
    
    private var onSpeedUpdate: ((Float, String) -> Void)?
    
    public init(onSpeedUpdate: @escaping (Float, String) -> Void) {
        self.onSpeedUpdate = onSpeedUpdate
        setupMotionTracking()
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates()
    }
    
    public func updateSpeed(
        frame: ARFrame,
        quality: Float,
        coverage: Float
    ) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // Calculate current speed from motion and frame data
        let currentSpeed = calculateCurrentSpeed(frame)
        speedHistory.append(currentSpeed)
        
        // Keep history size limited
        if speedHistory.count > historySize {
            speedHistory.removeFirst()
        }
        
        // Adjust optimal speed based on conditions
        adjustOptimalSpeed(
            quality: quality,
            coverage: coverage,
            currentSpeed: currentSpeed
        )
        
        // Generate guidance
        let speedRatio = currentSpeed / optimalSpeed
        let guidance = generateSpeedGuidance(speedRatio)
        
        onSpeedUpdate?(currentSpeed, guidance)
    }
    
    private func calculateCurrentSpeed(_ frame: ARFrame) -> Float {
        var speed: Float = 0
        
        // Calculate speed from camera movement
        let camera = frame.camera
        let translation = camera.transform.columns.3
        let position = SIMD3<Float>(translation.x, translation.y, translation.z)
        
        if let lastPosition = getLastPosition() {
            let displacement = position - lastPosition
            speed = length(displacement) / 0.1 // 100ms interval
        }
        
        // Incorporate device motion for more accuracy
        if let motion = motionManager.deviceMotion {
            let userAcceleration = motion.userAcceleration
            let accelerationMagnitude = Float(sqrt(
                userAcceleration.x * userAcceleration.x +
                userAcceleration.y * userAcceleration.y +
                userAcceleration.z * userAcceleration.z
            ))
            
            // Combine camera movement and acceleration
            speed = (speed + accelerationMagnitude) / 2
        }
        
        return speed
    }
    
    private func adjustOptimalSpeed(
        quality: Float,
        coverage: Float,
        currentSpeed: Float
    ) {
        // Base adjustment on scanning quality
        if quality < 0.3 {
            optimalSpeed *= 0.8 // Significantly slow down
        } else if quality < 0.7 {
            optimalSpeed *= 0.9 // Slightly slow down
        } else {
            optimalSpeed *= 1.1 // Speed up if quality is good
        }
        
        // Adjust based on coverage progress
        if coverage > 0.8 {
            optimalSpeed *= 0.9 // Slow down for fine details
        }
        
        // Consider movement stability
        let speedVariability = calculateSpeedVariability()
        if speedVariability > 0.5 {
            optimalSpeed *= 0.9 // Slow down if movement is unstable
        }
        
        // Clamp optimal speed to reasonable range
        optimalSpeed = min(max(optimalSpeed, 0.1), 1.0)
    }
    
    private func calculateSpeedVariability() -> Float {
        guard speedHistory.count > 1 else { return 0 }
        
        let mean = speedHistory.reduce(0, +) / Float(speedHistory.count)
        let variance = speedHistory.reduce(0) { sum, speed in
            sum + pow(speed - mean, 2)
        } / Float(speedHistory.count)
        
        return sqrt(variance) / mean
    }
    
    private func generateSpeedGuidance(_ speedRatio: Float) -> String {
        switch speedRatio {
        case 0..<0.5:
            return "Speed up slightly"
        case 0.5..<0.8:
            return "Good speed, continue"
        case 0.8..<1.2:
            return "Optimal scanning speed"
        case 1.2..<1.5:
            return "Slow down slightly"
        default:
            return "Moving too fast"
        }
    }
    
    private func getLastPosition() -> SIMD3<Float>? {
        // Calculate last position from speed history
        guard !speedHistory.isEmpty else { return nil }
        return SIMD3<Float>(0, 0, 0) // Placeholder for actual implementation
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}