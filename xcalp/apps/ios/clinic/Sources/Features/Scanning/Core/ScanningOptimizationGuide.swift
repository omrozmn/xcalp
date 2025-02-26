import Foundation
import ARKit
import CoreMotion

public struct OptimizationHint {
    let title: String
    let description: String
    let priority: Int // 1-5, with 5 being highest priority
    let actionRequired: Bool
}

public class ScanningOptimizationGuide {
    private let motionManager = CMMotionManager()
    private var lastMovementTime: TimeInterval = 0
    private var lastPositions: [SIMD3<Float>] = []
    private let positionHistoryLimit = 30
    private var isMovementStalled = false
    private var currentMovementPattern: MovementPattern = .unknown
    private var coverageGaps: [SIMD3<Float>] = []
    private var onHint: ((OptimizationHint) -> Void)?
    
    private enum MovementPattern {
        case linear
        case zigzag
        case circular
        case random
        case unknown
    }
    
    public init(onHint: @escaping (OptimizationHint) -> Void) {
        self.onHint = onHint
        setupMotionTracking()
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates()
    }
    
    public func analyzeScanningSession(
        frame: ARFrame,
        quality: Float,
        coverage: Float,
        points: [Point3D]
    ) {
        let camera = frame.camera
        let position = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        
        // Update position history
        lastPositions.append(position)
        if lastPositions.count > positionHistoryLimit {
            lastPositions.removeFirst()
        }
        
        // Analyze movement patterns
        analyzeMovement()
        
        // Check for coverage gaps
        analyzeCoverage(points: points, coverage: coverage)
        
        // Generate optimization hints based on analysis
        generateOptimizationHints(quality: quality, coverage: coverage)
    }
    
    private func analyzeMovement() {
        guard lastPositions.count > 2 else { return }
        
        // Calculate movement vectors between consecutive positions
        let movements = zip(lastPositions, lastPositions.dropFirst()).map { a, b in
            return b - a
        }
        
        // Check for stalled movement
        let totalMovement = movements.reduce(SIMD3<Float>(0, 0, 0), +)
        let movementMagnitude = length(totalMovement)
        isMovementStalled = movementMagnitude < 0.01
        
        // Analyze movement pattern
        let pattern = detectMovementPattern(movements)
        if pattern != currentMovementPattern {
            currentMovementPattern = pattern
            provideMovementGuidance()
        }
    }
    
    private func detectMovementPattern(_ movements: [SIMD3<Float>]) -> MovementPattern {
        // Calculate directional consistency
        let directions = movements.map { normalize($0) }
        let consistencyScore = calculateDirectionalConsistency(directions)
        
        if consistencyScore > 0.8 {
            return .linear
        } else if isZigzagPattern(directions) {
            return .zigzag
        } else if isCircularPattern(movements) {
            return .circular
        } else if consistencyScore < 0.3 {
            return .random
        }
        
        return .unknown
    }
    
    private func calculateDirectionalConsistency(_ directions: [SIMD3<Float>]) -> Float {
        guard !directions.isEmpty else { return 0 }
        
        let averageDirection = directions.reduce(SIMD3<Float>(0, 0, 0), +) / Float(directions.count)
        let normalizedAverage = normalize(averageDirection)
        
        let consistencyScores = directions.map { direction in
            return abs(dot(direction, normalizedAverage))
        }
        
        return consistencyScores.reduce(0, +) / Float(consistencyScores.count)
    }
    
    private func isZigzagPattern(_ directions: [SIMD3<Float>]) -> Bool {
        guard directions.count >= 4 else { return false }
        
        // Look for alternating directions
        for i in 0..<(directions.count - 2) {
            let dot1 = dot(directions[i], directions[i + 1])
            let dot2 = dot(directions[i + 1], directions[i + 2])
            
            if dot1 < -0.5 && dot2 < -0.5 {
                return true
            }
        }
        
        return false
    }
    
    private func isCircularPattern(_ movements: [SIMD3<Float>]) -> Bool {
        guard movements.count >= 8 else { return false }
        
        // Calculate angular changes
        var totalAngleChange: Float = 0
        for i in 0..<(movements.count - 1) {
            let angle = atan2(
                length(cross(movements[i], movements[i + 1])),
                dot(movements[i], movements[i + 1])
            )
            totalAngleChange += angle
        }
        
        // Check if total angle change is close to 2π
        return abs(totalAngleChange - 2 * Float.pi) < Float.pi / 4
    }
    
    private func analyzeCoverage(points: [Point3D], coverage: Float) {
        // Find areas with low point density
        let gridSize: Float = 0.1 // 10cm grid
        var grid: [SIMD3<Int>: Int] = [:]
        
        // Populate grid with point counts
        for point in points {
            let gridX = Int(point.x / gridSize)
            let gridY = Int(point.y / gridSize)
            let gridZ = Int(point.z / gridSize)
            let key = SIMD3<Int>(gridX, gridY, gridZ)
            grid[key, default: 0] += 1
        }
        
        // Find gaps in coverage
        coverageGaps = grid.filter { $0.value < 5 }.map { key, _ in
            SIMD3<Float>(
                Float(key.x) * gridSize,
                Float(key.y) * gridSize,
                Float(key.z) * gridSize
            )
        }
    }
    
    private func generateOptimizationHints(quality: Float, coverage: Float) {
        if isMovementStalled {
            onHint?(OptimizationHint(
                title: "Movement Stalled",
                description: "Continue moving the device to capture more area",
                priority: 4,
                actionRequired: true
            ))
        }
        
        if currentMovementPattern == .random && quality < 0.7 {
            onHint?(OptimizationHint(
                title: "Improve Scanning Pattern",
                description: "Use a more systematic side-to-side or circular motion",
                priority: 5,
                actionRequired: true
            ))
        }
        
        if !coverageGaps.isEmpty && coverage < 0.8 {
            onHint?(OptimizationHint(
                title: "Coverage Gaps Detected",
                description: "Move closer to highlighted areas to fill gaps",
                priority: 3,
                actionRequired: false
            ))
        }
        
        if quality < 0.5 {
            if let motion = motionManager.deviceMotion {
                let acceleration = motion.userAcceleration
                let isMovingTooFast = sqrt(
                    acceleration.x * acceleration.x +
                    acceleration.y * acceleration.y +
                    acceleration.z * acceleration.z
                ) > 0.5
                
                if isMovingTooFast {
                    onHint?(OptimizationHint(
                        title: "Movement Too Fast",
                        description: "Slow down for better scan quality",
                        priority: 5,
                        actionRequired: true
                    ))
                }
            }
        }
    }
    
    private func provideMovementGuidance() {
        switch currentMovementPattern {
        case .linear:
            onHint?(OptimizationHint(
                title: "Good Scanning Pattern",
                description: "Continue with steady linear movement",
                priority: 2,
                actionRequired: false
            ))
        case .zigzag:
            onHint?(OptimizationHint(
                title: "Effective Coverage Pattern",
                description: "Zigzag pattern is good for thorough coverage",
                priority: 2,
                actionRequired: false
            ))
        case .circular:
            onHint?(OptimizationHint(
                title: "Good Rotation Pattern",
                description: "Circular motion helps capture all angles",
                priority: 2,
                actionRequired: false
            ))
        case .random:
            onHint?(OptimizationHint(
                title: "Inconsistent Movement",
                description: "Try to maintain a more consistent scanning pattern",
                priority: 3,
                actionRequired: true
            ))
        case .unknown:
            break
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}