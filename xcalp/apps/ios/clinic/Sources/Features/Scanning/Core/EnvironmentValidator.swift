import Foundation
import ARKit
import CoreMotion
import CoreImage

public class EnvironmentValidator {
    private let motionManager = CMMotionManager()
    private var lastValidation = Date()
    private var validationHistory: [ValidationResult] = []
    private let historyLimit = 10
    private let ciContext = CICContext()
    
    private var onValidationUpdate: ((ValidationResult) -> Void)?
    
    public struct ValidationResult {
        let isValid: Bool
        let lightingQuality: Float
        let motionStability: Float
        let surfaceQuality: Float
        let environmentIssues: [EnvironmentIssue]
        
        var description: String {
            if isValid {
                return "Environment suitable for scanning"
            } else {
                return environmentIssues
                    .map { $0.description }
                    .joined(separator: "\n")
            }
        }
    }
    
    public enum EnvironmentIssue {
        case insufficientLight
        case excessiveMotion
        case poorSurfaceTexture
        case reflectiveSurface
        case outOfRange
        case unstablePlatform
        
        var description: String {
            switch self {
            case .insufficientLight:
                return "Area too dark - improve lighting"
            case .excessiveMotion:
                return "Device moving too fast"
            case .poorSurfaceTexture:
                return "Surface lacks detail - add visual markers"
            case .reflectiveSurface:
                return "Surface too reflective - reduce glare"
            case .outOfRange:
                return "Subject out of optimal range"
            case .unstablePlatform:
                return "Unstable scanning platform"
            }
        }
        
        var priority: Int {
            switch self {
            case .insufficientLight, .excessiveMotion:
                return 5
            case .poorSurfaceTexture, .reflectiveSurface:
                return 4
            case .outOfRange, .unstablePlatform:
                return 3
            }
        }
    }
    
    public init(onValidationUpdate: @escaping (ValidationResult) -> Void) {
        self.onValidationUpdate = onValidationUpdate
        setupMotionTracking()
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates()
    }
    
    public func validateEnvironment(frame: ARFrame) {
        guard shouldValidate() else { return }
        
        var issues: [EnvironmentIssue] = []
        
        // Check lighting conditions
        let lightingQuality = analyzeLighting(frame.capturedImage)
        if lightingQuality < 0.4 {
            issues.append(.insufficientLight)
        }
        
        // Check motion stability
        let motionStability = analyzeMotionStability()
        if motionStability < 0.5 {
            issues.append(.excessiveMotion)
        }
        
        // Check surface quality
        let surfaceQuality = analyzeSurfaceQuality(frame)
        if surfaceQuality < 0.3 {
            issues.append(.poorSurfaceTexture)
        }
        
        // Check for reflective surfaces
        if detectReflectiveSurfaces(frame) {
            issues.append(.reflectiveSurface)
        }
        
        // Check scanning range
        if !isInOptimalRange(frame.camera) {
            issues.append(.outOfRange)
        }
        
        // Check platform stability
        if !isPlatformStable() {
            issues.append(.unstablePlatform)
        }
        
        let result = ValidationResult(
            isValid: issues.isEmpty,
            lightingQuality: lightingQuality,
            motionStability: motionStability,
            surfaceQuality: surfaceQuality,
            environmentIssues: issues
        )
        
        updateValidationHistory(result)
        onValidationUpdate?(result)
        lastValidation = Date()
    }
    
    private func shouldValidate() -> Bool {
        return Date().timeIntervalSince(lastValidation) >= 1.0
    }
    
    private func analyzeLighting(_ pixelBuffer: CVPixelBuffer) -> Float {
        var totalBrightness: Float = 0
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        if let image = CIImage(cvPixelBuffer: pixelBuffer) {
            let averageFilter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: image,
                    kCIInputExtentKey: CIVector(
                        x: 0, y: 0,
                        z: Double(width),
                        w: Double(height)
                    )
                ]
            )
            
            if let outputImage = averageFilter?.outputImage {
                var bitmap = [UInt8](repeating: 0, count: 4)
                ciContext.render(
                    outputImage,
                    toBitmap: &bitmap,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
                
                let brightness = Float(bitmap[0] + bitmap[1] + bitmap[2]) / (255.0 * 3.0)
                totalBrightness = brightness
            }
        }
        
        return totalBrightness
    }
    
    private func analyzeMotionStability() -> Float {
        guard let motion = motionManager.deviceMotion else { return 1.0 }
        
        let acceleration = motion.userAcceleration
        let rotationRate = motion.rotationRate
        
        let accelerationMagnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        let rotationMagnitude = sqrt(
            rotationRate.x * rotationRate.x +
            rotationRate.y * rotationRate.y +
            rotationRate.z * rotationRate.z
        )
        
        // Scale and invert so higher values mean more stable
        let stabilityScore = 1.0 - min(
            1.0,
            (accelerationMagnitude * 2.0 + rotationMagnitude * 0.5)
        )
        
        return Float(stabilityScore)
    }
    
    private func analyzeSurfaceQuality(_ frame: ARFrame) -> Float {
        // Analyze feature points density and distribution
        let featurePoints = frame.rawFeaturePoints?.points ?? []
        guard !featurePoints.isEmpty else { return 0 }
        
        // Calculate point density
        let cameraTransform = frame.camera.transform
        let viewVolume = estimateViewVolume(camera: frame.camera)
        let density = Float(featurePoints.count) / viewVolume
        
        // Analyze point distribution
        let distribution = analyzePointDistribution(featurePoints)
        
        return min(density * 0.5 + distribution * 0.5, 1.0)
    }
    
    private func detectReflectiveSurfaces(_ frame: ARFrame) -> Bool {
        // Simple reflection detection based on brightness variation
        if let pixelBuffer = frame.capturedImage.clonePixelBuffer() {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            
            let edgeFilter = CIFilter(
                name: "CIEdges",
                parameters: [
                    kCIInputImageKey: image,
                    kCIInputIntensityKey: 1.0
                ]
            )
            
            if let edgeImage = edgeFilter?.outputImage {
                var bitmap = [UInt8](repeating: 0, count: 4)
                ciContext.render(
                    edgeImage,
                    toBitmap: &bitmap,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
                
                let edgeIntensity = Float(bitmap[0]) / 255.0
                return edgeIntensity > 0.7
            }
        }
        
        return false
    }
    
    private func isInOptimalRange(_ camera: ARCamera) -> Bool {
        // Check if scanning subject is within optimal distance range
        let position = camera.transform.columns.3
        let distance = sqrt(
            position.x * position.x +
            position.y * position.y +
            position.z * position.z
        )
        
        return distance >= 0.3 && distance <= 3.0
    }
    
    private func isPlatformStable() -> Bool {
        guard let attitude = motionManager.deviceMotion?.attitude else {
            return true
        }
        
        // Check if device is relatively level
        let roll = abs(attitude.roll)
        let pitch = abs(attitude.pitch)
        
        return roll < .pi/6 && pitch < .pi/6
    }
    
    private func estimateViewVolume(camera: ARCamera) -> Float {
        let fov = camera.intrinsics
        let distance = 1.0 // 1 meter reference distance
        
        let width = 2.0 * distance * tan(Double(fov[0][0]) / 2.0)
        let height = 2.0 * distance * tan(Double(fov[1][1]) / 2.0)
        
        return Float(width * height * distance)
    }
    
    private func analyzePointDistribution(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 1 else { return 0 }
        
        // Calculate point spread
        var minX = Float.infinity
        var maxX = -Float.infinity
        var minY = Float.infinity
        var maxY = -Float.infinity
        var minZ = Float.infinity
        var maxZ = -Float.infinity
        
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        
        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)
        let idealDensity = Float(points.count) / volume
        
        // Calculate actual density distribution
        var varianceSum: Float = 0
        let gridSize: Float = 0.1 // 10cm grid
        var grid: [SIMD3<Int>: Int] = [:]
        
        for point in points {
            let gridX = Int(point.x / gridSize)
            let gridY = Int(point.y / gridSize)
            let gridZ = Int(point.z / gridSize)
            let key = SIMD3<Int>(gridX, gridY, gridZ)
            grid[key, default: 0] += 1
        }
        
        for count in grid.values {
            let density = Float(count) / (gridSize * gridSize * gridSize)
            varianceSum += pow(density - idealDensity, 2)
        }
        
        let distributionScore = 1.0 - sqrt(varianceSum / Float(grid.count)) / idealDensity
        return max(0, min(distributionScore, 1.0))
    }
    
    private func updateValidationHistory(_ result: ValidationResult) {
        validationHistory.append(result)
        if validationHistory.count > historyLimit {
            validationHistory.removeFirst()
        }
    }
    
    public func getHistoricalValidation() -> ValidationResult? {
        guard !validationHistory.isEmpty else { return nil }
        
        let averageLighting = validationHistory.reduce(0) { $0 + $1.lightingQuality } / Float(validationHistory.count)
        let averageMotion = validationHistory.reduce(0) { $0 + $1.motionStability } / Float(validationHistory.count)
        let averageSurface = validationHistory.reduce(0) { $0 + $1.surfaceQuality } / Float(validationHistory.count)
        
        let persistentIssues = validationHistory
            .flatMap { $0.environmentIssues }
            .reduce(into: [:]) { counts, issue in
                counts[issue, default: 0] += 1
            }
            .filter { $0.value >= historyLimit / 2 }
            .map { $0.key }
        
        return ValidationResult(
            isValid: persistentIssues.isEmpty,
            lightingQuality: averageLighting,
            motionStability: averageMotion,
            surfaceQuality: averageSurface,
            environmentIssues: persistentIssues
        )
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

extension CVPixelBuffer {
    func clonePixelBuffer() -> CVPixelBuffer? {
        var pixelBufferCopy: CVPixelBuffer?
        
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let format = CVPixelBufferGetPixelFormatType(self)
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            nil,
            &pixelBufferCopy
        )
        
        if let copy = pixelBufferCopy {
            CVPixelBufferLockBaseAddress(self, .readOnly)
            CVPixelBufferLockBaseAddress(copy, [])
            
            let source = CVPixelBufferGetBaseAddress(self)
            let dest = CVPixelBufferGetBaseAddress(copy)
            let size = CVPixelBufferGetDataSize(self)
            
            memcpy(dest, source, size)
            
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
            
            return copy
        }
        
        return nil
    }
}