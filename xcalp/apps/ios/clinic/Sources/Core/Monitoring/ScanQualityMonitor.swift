import Foundation
import ARKit

class ScanQualityMonitor {
    static let shared = ScanQualityMonitor()
    private let medicalStandards = MedicalStandardsManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    private let analytics = AnalyticsService.shared
    
    // Quality thresholds per region
    private var qualityThresholds: [Region: ScanQualityThresholds] = [
        .unitedStates: .init(
            minLighting: 800.0,    // Lux
            minPointDensity: 1000,  // Points per cm²
            minAccuracy: 0.98,      // 98%
            maxMotion: 0.02         // 2% deviation
        ),
        .europeanUnion: .init(
            minLighting: 900.0,     // Lux
            minPointDensity: 1200,  // Points per cm²
            minAccuracy: 0.985,     // 98.5%
            maxMotion: 0.015        // 1.5% deviation
        ),
        .southAsia: .init(
            minLighting: 850.0,     // Lux
            minPointDensity: 1100,  // Points per cm²
            minAccuracy: 0.975,     // 97.5%
            maxMotion: 0.02         // 2% deviation
        ),
        .mediterranean: .init(
            minLighting: 950.0,     // Lux
            minPointDensity: 1150,  // Points per cm²
            minAccuracy: 0.98,      // 98%
            maxMotion: 0.018        // 1.8% deviation
        ),
        .africanDescent: .init(
            minLighting: 1000.0,    // Lux
            minPointDensity: 1300,  // Points per cm²
            minAccuracy: 0.99,      // 99%
            maxMotion: 0.01         // 1% deviation
        )
    ]
    
    private var currentQualityMetrics = QualityMetrics()
    private var qualityHistory: [QualityCheckpoint] = []
    
    func validateScanQuality(_ scan: ScanData) throws {
        performanceMonitor.startMeasuring("scan_quality_validation")
        defer { performanceMonitor.stopMeasuring("scan_quality_validation") }
        
        // Get regional thresholds
        let region = RegionalComplianceManager.shared.getCurrentRegion()
        guard let thresholds = qualityThresholds[region] else {
            throw QualityError.unsupportedRegion(region)
        }
        
        // Validate medical standards first
        try medicalStandards.validateMedicalStandards(for: scan)
        
        // Perform quality checks
        let metrics = try calculateQualityMetrics(scan)
        
        // Store metrics for trending
        updateQualityHistory(metrics)
        
        // Validate against thresholds
        try validateMetrics(metrics, against: thresholds)
        
        // Track quality metrics
        trackQualityMetrics(metrics, region: region)
    }
    
    func getCurrentQualityMetrics() -> QualityMetrics {
        return currentQualityMetrics
    }
    
    func getQualityTrend() -> QualityTrend {
        guard !qualityHistory.isEmpty else {
            return .stable
        }
        
        let recentMetrics = qualityHistory.suffix(5)
        let accuracyTrend = calculateTrend(recentMetrics.map { $0.metrics.accuracy })
        let densityTrend = calculateTrend(recentMetrics.map { Double($0.metrics.pointDensity) })
        
        if accuracyTrend < -0.05 || densityTrend < -0.05 {
            return .declining
        } else if accuracyTrend > 0.05 || densityTrend > 0.05 {
            return .improving
        }
        return .stable
    }
    
    private func calculateQualityMetrics(_ scan: ScanData) throws -> QualityMetrics {
        var metrics = QualityMetrics()
        
        metrics.lightingScore = scan.lightingScore
        metrics.pointDensity = scan.pointDensity
        metrics.accuracy = scan.accuracy
        metrics.motionScore = calculateMotionScore(scan)
        metrics.textureQuality = calculateTextureQuality(scan)
        metrics.calibrationStatus = scan.isCalibrated
        
        currentQualityMetrics = metrics
        return metrics
    }
    
    private func validateMetrics(_ metrics: QualityMetrics, against thresholds: ScanQualityThresholds) throws {
        if metrics.lightingScore < thresholds.minLighting {
            throw QualityError.insufficientLighting(
                current: metrics.lightingScore,
                required: thresholds.minLighting
            )
        }
        
        if metrics.pointDensity < thresholds.minPointDensity {
            throw QualityError.insufficientDensity(
                current: metrics.pointDensity,
                required: thresholds.minPointDensity
            )
        }
        
        if metrics.accuracy < thresholds.minAccuracy {
            throw QualityError.insufficientAccuracy(
                current: metrics.accuracy,
                required: thresholds.minAccuracy
            )
        }
        
        if metrics.motionScore > thresholds.maxMotion {
            throw QualityError.excessiveMotion(
                current: metrics.motionScore,
                maximum: thresholds.maxMotion
            )
        }
    }
    
    private func calculateMotionScore(_ scan: ScanData) -> Float {
        // Implementation would analyze frame-to-frame motion
        return 0.01 // Example value
    }
    
    private func calculateTextureQuality(_ scan: ScanData) -> Float {
        // Implementation would analyze texture resolution and clarity
        return 0.95 // Example value
    }
    
    private func updateQualityHistory(_ metrics: QualityMetrics) {
        let checkpoint = QualityCheckpoint(timestamp: Date(), metrics: metrics)
        qualityHistory.append(checkpoint)
        
        // Keep last 50 checkpoints
        if qualityHistory.count > 50 {
            qualityHistory.removeFirst()
        }
    }
    
    private func calculateTrend(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        
        let xValues = Array(0..<values.count).map(Double.init)
        let yValues = values
        
        let sumX = xValues.reduce(0, +)
        let sumY = yValues.reduce(0, +)
        let sumXY = zip(xValues, yValues).map(*).reduce(0, +)
        let sumXX = xValues.map { $0 * $0 }.reduce(0, +)
        
        let n = Double(values.count)
        let slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX)
        
        return slope
    }
    
    private func trackQualityMetrics(_ metrics: QualityMetrics, region: Region) {
        analytics.trackEvent(
            category: .quality,
            action: "scan_quality",
            label: region.rawValue,
            value: Int(metrics.accuracy * 100),
            metadata: [
                "lighting": String(metrics.lightingScore),
                "density": String(metrics.pointDensity),
                "motion": String(metrics.motionScore),
                "texture": String(metrics.textureQuality),
                "calibrated": String(metrics.calibrationStatus)
            ]
        )
    }
}

// MARK: - Supporting Types

struct ScanQualityThresholds {
    let minLighting: Float
    let minPointDensity: Int
    let minAccuracy: Float
    let maxMotion: Float
}

struct QualityMetrics {
    var lightingScore: Float = 0
    var pointDensity: Int = 0
    var accuracy: Float = 0
    var motionScore: Float = 0
    var textureQuality: Float = 0
    var calibrationStatus: Bool = false
}

struct QualityCheckpoint {
    let timestamp: Date
    let metrics: QualityMetrics
}

enum QualityTrend {
    case improving
    case stable
    case declining
}

enum QualityError: LocalizedError {
    case unsupportedRegion(Region)
    case insufficientLighting(current: Float, required: Float)
    case insufficientDensity(current: Int, required: Int)
    case insufficientAccuracy(current: Float, required: Float)
    case excessiveMotion(current: Float, maximum: Float)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Quality thresholds not defined for region: \(region)"
        case .insufficientLighting(let current, let required):
            return "Insufficient lighting: \(current) lux (required: \(required) lux)"
        case .insufficientDensity(let current, let required):
            return "Insufficient point density: \(current) points/cm² (required: \(required) points/cm²)"
        case .insufficientAccuracy(let current, let required):
            return "Insufficient accuracy: \(current * 100)% (required: \(required * 100)%)"
        case .excessiveMotion(let current, let maximum):
            return "Excessive motion detected: \(current * 100)% (maximum: \(maximum * 100)%)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .insufficientLighting:
            return "Try moving to a better lit area or adding additional lighting"
        case .insufficientDensity:
            return "Move the device closer to the scan area"
        case .insufficientAccuracy:
            return "Ensure the device is properly calibrated and scan more slowly"
        case .excessiveMotion:
            return "Hold the device more steady while scanning"
        default:
            return nil
        }
    }
}