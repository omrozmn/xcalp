import Foundation
import ARKit
import CoreMotion
import os.log
import CoreImage
import MetalKit

final class ScanningGuidanceSystem {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningGuidance")
    private let motionManager = CMMotionManager()
    private var currentState: ScanningState = .preparing
    private var coverageMap: [Bool] = Array(repeating: false, count: 8) // 8 primary angles
    
    enum ScanningState {
        case preparing
        case scanning
        case adjusting
        case completing
        case reviewing
    }
    
    struct GuidanceUpdate {
        let message: String
        let progress: Float
        let suggestedAction: SuggestedAction?
        let visualGuide: VisualGuide?
    }
    
    enum SuggestedAction {
        case moveCloser
        case moveFurther
        case moveSlower
        case adjustAngle(Float)
        case improveLight
        case holdSteady
        case scanMissingArea(CGRect)
    }
    
    enum VisualGuide {
        case targetPosition(CGPoint)
        case scanPath([CGPoint])
        case coverageArea(CGRect)
        case qualityHeatmap([[Float]])
    }
    
    init() {
        setupMotionTracking()
    }
    
    func startGuidance() {
        currentState = .preparing
        resetCoverageMap()
    }
    
    func updateGuidance(frame: ARFrame) -> GuidanceUpdate {
        let perfID = PerformanceMonitor.shared.startMeasuring("guidanceUpdate")
        defer { PerformanceMonitor.shared.endMeasuring("guidanceUpdate", signpostID: perfID) }
        
        var guidance = GuidanceUpdate()
        
        // Coverage analysis
        let coverage = calculateCoverage(frame)
        if coverage < 0.95 {
            guidance.coverageGaps = findCoverageGaps(frame)
            guidance.suggestedViewpoints = calculateOptimalViewpoints(gaps: guidance.coverageGaps)
        }
        
        // Quality monitoring
        let quality = assessQuality(frame)
        if quality < 0.8 {
            guidance.qualityIssues = detectQualityIssues(frame)
            guidance.improvementSuggestions = generateQualitySuggestions(guidance.qualityIssues)
        }
        
        // Motion stability
        if let motionIssue = checkMotionStability(frame) {
            guidance.motionWarning = motionIssue
            guidance.stabilizationTips = getStabilizationTips(for: motionIssue)
        }
        
        // Lighting recommendations
        if let lightingIssue = checkLightingConditions(frame) {
            guidance.lightingWarning = lightingIssue
            guidance.lightingTips = getLightingTips(for: lightingIssue)
        }
        
        return guidance
    }
    
    private func analyzeFrame(_ frame: ARFrame) -> FrameMetrics {
        let coverage = calculateCoverage(frame)
        let quality = assessQuality(frame)
        let stability = checkStability(frame)
        
        return FrameMetrics(
            coverage: coverage,
            quality: quality,
            stability: stability
        )
    }
    
    private func calculateCoverage(_ frame: ARFrame) -> Float {
        guard let sceneDepth = frame.sceneDepth else { return 0 }
        
        let depthMap = sceneDepth.depthMap
        var validPixels = 0
        var totalPixels = 0
        
        // Analyze depth map coverage
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixel = baseAddress?.advanced(by: y * bytesPerRow + x * 4)
                    .assumingMemoryBound(to: Float32.self)
                if let depth = pixel?.pointee, depth > 0 {
                    validPixels += 1
                }
                totalPixels += 1
            }
        }
        
        return Float(validPixels) / Float(totalPixels)
    }
    
    private func assessQuality(_ frame: ARFrame) -> Float {
        guard let sceneDepth = frame.sceneDepth,
              let confidenceMap = sceneDepth.confidenceMap else { return 0 }
        
        var totalConfidence: Float = 0
        var pixelCount = 0
        
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap)
        
        for y in 0..<height {
            for x in 0..<width {
                if let confidence = baseAddress?.advanced(by: y * bytesPerRow + x)
                    .assumingMemoryBound(to: UInt8.self).pointee {
                    totalConfidence += Float(confidence) / 255.0
                    pixelCount += 1
                }
            }
        }
        
        return pixelCount > 0 ? totalConfidence / Float(pixelCount) : 0
    }
    
    private func checkStability(_ frame: ARFrame) -> Float {
        guard let deviceMotion = motionManager.deviceMotion else { return 0 }
        
        let rotationRate = deviceMotion.rotationRate
        let userAcceleration = deviceMotion.userAcceleration
        
        // Calculate stability score based on device motion
        let rotationMagnitude = sqrt(
            pow(rotationRate.x, 2) +
            pow(rotationRate.y, 2) +
            pow(rotationRate.z, 2)
        )
        
        let accelerationMagnitude = sqrt(
            pow(userAcceleration.x, 2) +
            pow(userAcceleration.y, 2) +
            pow(userAcceleration.z, 2)
        )
        
        // Normalize and combine scores
        let rotationScore = 1.0 - min(rotationMagnitude / 5.0, 1.0)
        let accelerationScore = 1.0 - min(accelerationMagnitude / 2.0, 1.0)
        
        return Float((rotationScore + accelerationScore) / 2.0)
    }
    
    private func handlePreparationState(_ metrics: FrameMetrics) -> GuidanceUpdate {
        if metrics.stability < 0.7 {
            return GuidanceUpdate(
                message: "Hold the device steady",
                progress: 0,
                suggestedAction: .holdSteady,
                visualGuide: nil
            )
        }
        
        if metrics.quality < 0.6 {
            return GuidanceUpdate(
                message: "Move to a well-lit area",
                progress: 0,
                suggestedAction: .improveLight,
                visualGuide: nil
            )
        }
        
        currentState = .scanning
        return GuidanceUpdate(
            message: "Ready to start scanning",
            progress: 0,
            suggestedAction: nil,
            visualGuide: nil
        )
    }
    
    private func handleScanningState(_ frame: ARFrame, _ metrics: FrameMetrics, _ motion: CMDeviceMotion?) -> GuidanceUpdate {
        updateCoverageMap(frame)
        let progress = calculateProgress()
        
        if let missingArea = findLargestMissingArea() {
            return GuidanceUpdate(
                message: "Scan missing area",
                progress: progress,
                suggestedAction: .scanMissingArea(missingArea),
                visualGuide: .coverageArea(missingArea)
            )
        }
        
        if metrics.stability < 0.5 {
            return GuidanceUpdate(
                message: "Moving too fast",
                progress: progress,
                suggestedAction: .moveSlower,
                visualGuide: nil
            )
        }
        
        if progress > 0.95 {
            currentState = .completing
        }
        
        return GuidanceUpdate(
            message: "Continue scanning...",
            progress: progress,
            suggestedAction: nil,
            visualGuide: .scanPath(calculateOptimalScanPath())
        )
    }
    
    private func handleAdjustmentState(_ metrics: FrameMetrics) -> GuidanceUpdate {
        if metrics.quality < 0.7 {
            let targetDistance = estimateOptimalDistance(metrics)
            let action: SuggestedAction = targetDistance > 0 ? .moveCloser : .moveFurther
            
            return GuidanceUpdate(
                message: "Adjust position for better quality",
                progress: calculateProgress(),
                suggestedAction: action,
                visualGuide: .targetPosition(calculateOptimalPosition())
            )
        }
        
        currentState = .scanning
        return GuidanceUpdate(
            message: "Quality improved, continue scanning",
            progress: calculateProgress(),
            suggestedAction: nil,
            visualGuide: nil
        )
    }
    
    private func handleCompletionState() -> GuidanceUpdate {
        currentState = .reviewing
        return GuidanceUpdate(
            message: "Scan complete. Reviewing quality...",
            progress: 1.0,
            suggestedAction: nil,
            visualGuide: nil
        )
    }
    
    private func handleReviewState(_ metrics: FrameMetrics) -> GuidanceUpdate {
        if metrics.quality < 0.8 {
            currentState = .adjusting
            return GuidanceUpdate(
                message: "Quality needs improvement",
                progress: 1.0,
                suggestedAction: .improveLight,
                visualGuide: .qualityHeatmap(generateQualityHeatmap())
            )
        }
        
        return GuidanceUpdate(
            message: "Scan quality acceptable",
            progress: 1.0,
            suggestedAction: nil,
            visualGuide: nil
        )
    }
    
    private func setupMotionTracking() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates()
        }
    }
    
    private func resetCoverageMap() {
        coverageMap = Array(repeating: false, count: 8)
    }
    
    private func updateCoverageMap(_ frame: ARFrame) {
        let camera = frame.camera
        let angle = atan2(camera.eulerAngles.y, camera.eulerAngles.x)
        let sector = Int((angle + .pi) / (.pi / 4)) % 8
        coverageMap[sector] = true
    }
    
    private func calculateProgress() -> Float {
        let coveredSectors = coverageMap.filter { $0 }.count
        return Float(coveredSectors) / Float(coverageMap.count)
    }
    
    private func findLargestMissingArea() -> CGRect? {
        // Implementation to find largest uncovered area
        return nil
    }
    
    private func calculateOptimalScanPath() -> [CGPoint] {
        // Calculate optimal path based on coverage
        return []
    }
    
    private func estimateOptimalDistance(_ metrics: FrameMetrics) -> Float {
        // Estimate optimal scanning distance
        return 0.0
    }
    
    private func calculateOptimalPosition() -> CGPoint {
        // Calculate optimal device position
        return .zero
    }
    
    private func generateQualityHeatmap() -> [[Float]] {
        // Generate quality heatmap
        return []
    }
    
    private func findCoverageGaps(_ frame: ARFrame) -> [CoverageGap] {
        guard let depthMap = frame.sceneDepth?.depthMap else { return [] }
        
        return autoreleasepool {
            let gaps = findGapsInDepthMap(depthMap)
            return gaps.compactMap { gap in
                guard validateGapSignificance(gap, confidence: frame.sceneDepth?.confidenceMap) else {
                    return nil
                }
                return gap
            }
        }
    }
    
    private func findGapsInDepthMap(_ depthMap: CVPixelBuffer) -> [CoverageGap] {
        var gaps: [CoverageGap] = []
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Use Metal for parallel gap detection if available
        if let gapDetector = try? MetalGapDetector(width: width, height: height) {
            gaps = gapDetector.detectGaps(in: depthMap)
        } else {
            // Fallback to CPU-based detection
            gaps = detectGapsOnCPU(depthMap, width: width, height: height)
        }
        
        return mergeAdjacentGaps(gaps)
    }

    private func validateGapSignificance(_ gap: CoverageGap, confidence: CVPixelBuffer?) -> Bool {
        // Validate gap size and surrounding depth consistency
        let minGapSize = CGSize(width: 10, height: 10)
        guard gap.bounds.size.width >= minGapSize.width &&
              gap.bounds.size.height >= minGapSize.height else {
            return false
        }
        
        // Check confidence map if available
        if let confidenceMap = confidence {
            return validateGapConfidence(gap, confidenceMap: confidenceMap)
        }
        
        return true
    }
    
    private func validateGapConfidence(_ gap: CoverageGap, confidenceMap: CVPixelBuffer) -> Bool {
        let surroundingConfidence = calculateSurroundingConfidence(gap, in: confidenceMap)
        return surroundingConfidence > 0.7 // Only consider gaps in high-confidence regions
    }
    
    private func generateQualitySuggestions(_ issues: [QualityIssue]) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        for issue in issues {
            switch issue {
            case .lowPointDensity:
                suggestions.append(Suggestion(
                    "Move closer to capture more detail",
                    priority: .high,
                    additionalContext: "Maintain 20-30cm distance from surface"
                ))
            case .highNoise:
                suggestions.append(Suggestion(
                    "Hold device more steady",
                    priority: .medium,
                    additionalContext: "Rest your elbows against your body for stability"
                ))
            case .incompleteFeatures:
                suggestions.append(Suggestion(
                    "Scan from multiple angles",
                    priority: .high,
                    additionalContext: "Move in a smooth arc pattern, 45° at a time"
                ))
            case .poorLighting:
                suggestions.append(Suggestion(
                    "Improve lighting conditions",
                    priority: .medium,
                    additionalContext: "Ensure even lighting without harsh shadows"
                ))
            case .excessiveMotion:
                suggestions.append(Suggestion(
                    "Slow down scanning movement",
                    priority: .high,
                    additionalContext: "Move at about 10cm per second"
                ))
            default:
                suggestions.append(Suggestion(
                    "Adjust scanning position",
                    priority: .low,
                    additionalContext: "Maintain consistent distance and speed"
                ))
            }
        }
        
        return suggestions.sorted { $0.priority > $1.priority }
    }
}

// Supporting types
struct FrameMetrics {
    let coverage: Float
    let quality: Float
    let stability: Float
}

struct CoverageGap {
    let bounds: CGRect
    let averageDepth: Float
    let confidence: Float
}

private class MetalGapDetector {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    init(width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "detectGapsKernel"),
              let pipelineState = try? device.makeComputePipelineState(function: function) else {
            throw GuidanceError.metalInitializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
    }
    
    func detectGaps(in depthMap: CVPixelBuffer) -> [CoverageGap] {
        // Implement Metal-accelerated gap detection
        // This is a placeholder - actual implementation would use Metal compute shader
        return []
    }
}

enum GuidanceError: Error {
    case metalInitializationFailed
    case invalidDepthMap
    case invalidConfidenceMap
}