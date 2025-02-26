import ARKit
import Metal
import CoreML
import os.log

final class ScanningQualityAnalyzer {
    static let shared = ScanningQualityAnalyzer()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "QualityAnalysis")
    private let performanceMonitor = PerformanceMonitor.shared
    private let mlModel: QualityPredictionModel?
    
    private var analysisHistory: RingBuffer<QualityAnalysis>
    private let predictionQueue = DispatchQueue(label: "com.xcalp.quality.prediction", qos: .userInteractive)
    private var isMonitoring = false
    
    private init() {
        self.analysisHistory = RingBuffer(capacity: 300) // 5 minutes at 1Hz
        self.mlModel = try? QualityPredictionModel()
        setupQualityMonitoring()
    }
    
    struct QualityAnalysis: Codable {
        let timestamp: Date
        let metrics: QualityMetrics
        let prediction: QualityPrediction
        let recommendations: [QualityRecommendation]
        
        var meetsRequirements: Bool {
            metrics.meetsMinimumRequirements &&
            prediction.confidence > ClinicalConstants.minimumPredictionConfidence
        }
    }
    
    struct QualityMetrics: Codable {
        let pointDensity: Float
        let featureQuality: Float
        let surfaceConsistency: Float
        let lightingQuality: Float
        let motionStability: Float
        let depthAccuracy: Float
        
        var meetsMinimumRequirements: Bool {
            pointDensity >= ClinicalConstants.minimumPointDensity &&
            featureQuality >= ClinicalConstants.minFeatureMatchConfidence &&
            surfaceConsistency >= ClinicalConstants.surfaceConsistencyThreshold &&
            lightingQuality >= ClinicalConstants.minimumLightingQuality &&
            motionStability >= ClinicalConstants.minimumMotionStability &&
            depthAccuracy >= ClinicalConstants.minimumDepthAccuracy
        }
    }
    
    struct QualityPrediction: Codable {
        let overallQuality: Float
        let confidence: Float
        let potentialIssues: [QualityIssue]
        
        enum QualityIssue: String, Codable {
            case insufficientLighting
            case excessiveMotion
            case poorFeatureTracking
            case inconsistentDepth
            case insufficientCoverage
        }
    }
    
    struct QualityRecommendation: Codable {
        let type: RecommendationType
        let priority: Priority
        let currentValue: Float
        let targetValue: Float
        let message: String
        
        enum RecommendationType: String, Codable {
            case adjustLighting
            case stabilizeDevice
            case adjustDistance
            case improveAngle
            case increaseCoverage
        }
        
        enum Priority: Int, Codable {
            case low = 0
            case medium = 1
            case high = 2
        }
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Started quality monitoring")
        
        // Schedule periodic analysis
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.performPeriodicAnalysis()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        logger.info("Stopped quality monitoring")
    }
    
    func analyzeFrame(_ frame: ARFrame) async -> QualityAnalysis {
        // Extract frame metrics
        let metrics = extractQualityMetrics(frame)
        
        // Generate quality prediction
        let prediction = await predictQuality(metrics: metrics, frame: frame)
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            metrics: metrics,
            prediction: prediction,
            frame: frame
        )
        
        let analysis = QualityAnalysis(
            timestamp: Date(),
            metrics: metrics,
            prediction: prediction,
            recommendations: recommendations
        )
        
        // Store analysis result
        analysisHistory.append(analysis)
        
        // Notify observers if quality issues detected
        if !analysis.meetsRequirements {
            notifyQualityIssues(analysis)
        }
        
        return analysis
    }
    
    // MARK: - Private Methods
    
    private func extractQualityMetrics(_ frame: ARFrame) -> QualityMetrics {
        // Extract and calculate core metrics
        let pointCloud = frame.rawFeaturePoints?.points ?? []
        let lightEstimate = frame.lightEstimate?.ambientIntensity ?? 0
        
        return QualityMetrics(
            pointDensity: calculatePointDensity(pointCloud),
            featureQuality: calculateFeatureQuality(frame),
            surfaceConsistency: calculateSurfaceConsistency(frame),
            lightingQuality: Float(lightEstimate / 1000.0), // Convert to normalized value
            motionStability: calculateMotionStability(frame.camera),
            depthAccuracy: calculateDepthAccuracy(frame.sceneDepth)
        )
    }
    
    private func predictQuality(
        metrics: QualityMetrics,
        frame: ARFrame
    ) async -> QualityPrediction {
        await withCheckedContinuation { continuation in
            predictionQueue.async {
                var potentialIssues: [QualityPrediction.QualityIssue] = []
                var overallQuality: Float = 1.0
                var confidence: Float = 1.0
                
                // Check lighting
                if metrics.lightingQuality < ClinicalConstants.minimumLightingQuality {
                    potentialIssues.append(.insufficientLighting)
                    overallQuality *= metrics.lightingQuality
                    confidence *= 0.8
                }
                
                // Check motion stability
                if metrics.motionStability < ClinicalConstants.minimumMotionStability {
                    potentialIssues.append(.excessiveMotion)
                    overallQuality *= metrics.motionStability
                    confidence *= 0.7
                }
                
                // Check feature tracking
                if metrics.featureQuality < ClinicalConstants.minFeatureMatchConfidence {
                    potentialIssues.append(.poorFeatureTracking)
                    overallQuality *= metrics.featureQuality
                    confidence *= 0.9
                }
                
                // Check depth accuracy
                if metrics.depthAccuracy < ClinicalConstants.minimumDepthAccuracy {
                    potentialIssues.append(.inconsistentDepth)
                    overallQuality *= metrics.depthAccuracy
                    confidence *= 0.85
                }
                
                // Use ML model for enhanced prediction if available
                if let model = self.mlModel {
                    do {
                        let prediction = try model.prediction(
                            pointDensity: Double(metrics.pointDensity),
                            featureQuality: Double(metrics.featureQuality),
                            surfaceConsistency: Double(metrics.surfaceConsistency),
                            lightingQuality: Double(metrics.lightingQuality),
                            motionStability: Double(metrics.motionStability),
                            depthAccuracy: Double(metrics.depthAccuracy)
                        )
                        
                        overallQuality = min(overallQuality, Float(prediction.qualityScore))
                        confidence = min(confidence, Float(prediction.confidence))
                    } catch {
                        self.logger.error("ML prediction failed: \(error.localizedDescription)")
                    }
                }
                
                continuation.resume(returning: QualityPrediction(
                    overallQuality: overallQuality,
                    confidence: confidence,
                    potentialIssues: potentialIssues
                ))
            }
        }
    }
    
    private func generateRecommendations(
        metrics: QualityMetrics,
        prediction: QualityPrediction,
        frame: ARFrame
    ) -> [QualityRecommendation] {
        var recommendations: [QualityRecommendation] = []
        
        // Check lighting issues
        if prediction.potentialIssues.contains(.insufficientLighting) {
            recommendations.append(QualityRecommendation(
                type: .adjustLighting,
                priority: .high,
                currentValue: metrics.lightingQuality,
                targetValue: ClinicalConstants.minimumLightingQuality,
                message: "Increase lighting in the scanning area"
            ))
        }
        
        // Check motion stability
        if prediction.potentialIssues.contains(.excessiveMotion) {
            recommendations.append(QualityRecommendation(
                type: .stabilizeDevice,
                priority: .high,
                currentValue: metrics.motionStability,
                targetValue: ClinicalConstants.minimumMotionStability,
                message: "Hold the device more stable"
            ))
        }
        
        // Check scanning distance
        let currentDistance = calculateScanningDistance(frame)
        if currentDistance > 0.6 || currentDistance < 0.2 {
            recommendations.append(QualityRecommendation(
                type: .adjustDistance,
                priority: .medium,
                currentValue: currentDistance,
                targetValue: 0.4,
                message: "Adjust scanning distance to 40cm"
            ))
        }
        
        // Check scanning angle
        let currentAngle = calculateScanningAngle(frame)
        if abs(currentAngle) > .pi / 4 {
            recommendations.append(QualityRecommendation(
                type: .improveAngle,
                priority: .medium,
                currentValue: currentAngle,
                targetValue: 0,
                message: "Keep the device perpendicular to the surface"
            ))
        }
        
        return recommendations.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    private func performPeriodicAnalysis() {
        guard isMonitoring else { return }
        
        // Analyze quality trends
        let recentAnalyses = analysisHistory.elements.suffix(10)
        let qualityTrend = calculateQualityTrend(recentAnalyses)
        
        // Check for persistent issues
        let persistentIssues = findPersistentIssues(recentAnalyses)
        
        if !persistentIssues.isEmpty {
            notifyPersistentIssues(persistentIssues)
        }
        
        // Log quality status
        logger.debug("""
            Quality trend: \(String(format: "%.2f", qualityTrend))
            Persistent issues: \(persistentIssues.map { $0.rawValue }.joined(separator: ", "))
            """)
    }
    
    private func calculateQualityTrend(_ analyses: ArraySlice<QualityAnalysis>) -> Float {
        let qualityScores = analyses.map { $0.prediction.overallQuality }
        return qualityScores.reduce(0, +) / Float(qualityScores.count)
    }
    
    private func findPersistentIssues(
        _ analyses: ArraySlice<QualityAnalysis>
    ) -> [QualityPrediction.QualityIssue] {
        var issueCounts: [QualityPrediction.QualityIssue: Int] = [:]
        
        for analysis in analyses {
            for issue in analysis.prediction.potentialIssues {
                issueCounts[issue, default: 0] += 1
            }
        }
        
        // Consider issues that appear in more than 70% of recent analyses
        let threshold = Int(Double(analyses.count) * 0.7)
        return issueCounts.filter { $0.value >= threshold }.map { $0.key }
    }
    
    private func notifyQualityIssues(_ analysis: QualityAnalysis) {
        NotificationCenter.default.post(
            name: .qualityIssuesDetected,
            object: nil,
            userInfo: [
                "analysis": analysis,
                "recommendations": analysis.recommendations
            ]
        )
    }
    
    private func notifyPersistentIssues(_ issues: [QualityPrediction.QualityIssue]) {
        NotificationCenter.default.post(
            name: .persistentQualityIssues,
            object: nil,
            userInfo: ["issues": issues]
        )
    }
    
    private func setupQualityMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScanningStateChange),
            name: .scanningDidStart,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScanningStateChange),
            name: .scanningDidStop,
            object: nil
        )
    }
    
    @objc private func handleScanningStateChange(_ notification: Notification) {
        if notification.name == .scanningDidStart {
            startMonitoring()
        } else if notification.name == .scanningDidStop {
            stopMonitoring()
        }
    }
}

// MARK: - Supporting Methods

extension ScanningQualityAnalyzer {
    private func calculatePointDensity(_ points: [SIMD3<Float>]) -> Float {
        guard !points.isEmpty else { return 0 }
        
        // Calculate bounding volume
        let boundingBox = points.reduce(BoundingBox()) { box, point in
            box.union(with: point)
        }
        
        let volume = boundingBox.volume
        return volume > 0 ? Float(points.count) / volume : 0
    }
    
    private func calculateFeatureQuality(_ frame: ARFrame) -> Float {
        guard let features = frame.rawFeaturePoints else { return 0 }
        
        let featureCount = Float(features.points.count)
        let idealFeatureCount: Float = 200 // Based on empirical testing
        
        return min(featureCount / idealFeatureCount, 1.0)
    }
    
    private func calculateSurfaceConsistency(_ frame: ARFrame) -> Float {
        guard let depthMap = frame.sceneDepth?.depthMap else { return 0 }
        
        // Calculate depth consistency in local neighborhoods
        var consistency: Float = 0
        // Implementation details...
        return consistency
    }
    
    private func calculateMotionStability(_ camera: ARCamera) -> Float {
        let rotationRate = camera.eulerAngles
        let translationRate = camera.deviceMotion?.userAcceleration ?? .zero
        
        // Calculate stability score based on motion
        let rotationMagnitude = length(rotationRate)
        let translationMagnitude = length(SIMD3(
            Float(translationRate.x),
            Float(translationRate.y),
            Float(translationRate.z)
        ))
        
        let rotationThreshold: Float = 0.5
        let translationThreshold: Float = 0.2
        
        let rotationStability = 1.0 - min(rotationMagnitude / rotationThreshold, 1.0)
        let translationStability = 1.0 - min(translationMagnitude / translationThreshold, 1.0)
        
        return min(rotationStability, translationStability)
    }
    
    private func calculateDepthAccuracy(_ depthMap: ARDepthData?) -> Float {
        guard let depthMap = depthMap else { return 0 }
        
        // Calculate depth accuracy based on confidence map
        var accuracy: Float = 0
        // Implementation details...
        return accuracy
    }
    
    private func calculateScanningDistance(_ frame: ARFrame) -> Float {
        // Calculate average distance to detected surface
        guard let depthMap = frame.sceneDepth?.depthMap else { return 0 }
        
        var totalDepth: Float = 0
        var validSamples = 0
        
        // Sample depth values
        // Implementation details...
        
        return validSamples > 0 ? totalDepth / Float(validSamples) : 0
    }
    
    private func calculateScanningAngle(_ frame: ARFrame) -> Float {
        // Calculate angle between camera normal and detected surface normal
        let cameraTransform = frame.camera.transform
        let surfaceNormal = estimateSurfaceNormal(frame)
        
        return acos(dot(
            normalize(SIMD3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)),
            normalize(surfaceNormal)
        ))
    }
    
    private func estimateSurfaceNormal(_ frame: ARFrame) -> SIMD3<Float> {
        guard let points = frame.rawFeaturePoints?.points, points.count >= 3 else {
            return SIMD3(0, 0, 1)
        }
        
        // Estimate surface normal using PCA
        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        var covarianceMatrix = matrix_float3x3()
        
        for point in points {
            let centered = point - centroid
            covarianceMatrix.columns.0 += centered * centered.x
            covarianceMatrix.columns.1 += centered * centered.y
            covarianceMatrix.columns.2 += centered * centered.z
        }
        
        covarianceMatrix = covarianceMatrix / Float(points.count)
        
        // Find eigenvector with smallest eigenvalue (surface normal)
        // Implementation details...
        
        return normalize(SIMD3(0, 0, 1)) // Placeholder
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let qualityIssuesDetected = Notification.Name("qualityIssuesDetected")
    static let persistentQualityIssues = Notification.Name("persistentQualityIssues")
}

// MARK: - Supporting Types

struct BoundingBox {
    var min = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
    var max = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
    
    mutating func union(with point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }
    
    var volume: Float {
        let dimensions = max - min
        return dimensions.x * dimensions.y * dimensions.z
    }
}