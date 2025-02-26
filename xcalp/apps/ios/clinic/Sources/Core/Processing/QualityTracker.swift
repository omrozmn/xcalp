import Foundation
import Metal
import os.log

final class QualityTracker {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "QualityTracker")
    private var qualityHistory: [(timestamp: TimeInterval, metrics: QualityMetrics)] = []
    private let historyDuration: TimeInterval = 5.0 // Keep 5 seconds of history
    
    // Quality thresholds from updated requirements
    private let thresholds = QualityThresholds(
        minDensity: 750,
        maxDensity: 1200,
        minCompleteness: 0.985,
        maxNoise: 0.08,
        minFeaturePreservation: 0.97,
        minCurvatureAccuracy: 0.05
    )
    
    func addQualityMetrics(_ metrics: QualityMetrics) {
        let currentTime = CACurrentMediaTime()
        qualityHistory.append((currentTime, metrics))
        
        // Remove old entries
        qualityHistory = qualityHistory.filter {
            currentTime - $0.timestamp < historyDuration
        }
        
        // Log significant quality changes
        if let trend = analyzeTrend() {
            logger.info("Quality trend detected: \(trend)")
        }
    }
    
    func getAverageMetrics(duration: TimeInterval) -> QualityMetrics? {
        let currentTime = CACurrentMediaTime()
        let relevantMetrics = qualityHistory.filter {
            currentTime - $0.timestamp < duration
        }
        
        guard !relevantMetrics.isEmpty else { return nil }
        
        return QualityMetrics(
            pointDensity: relevantMetrics.map { $0.metrics.pointDensity }.reduce(0, +) / Double(relevantMetrics.count),
            surfaceCompleteness: relevantMetrics.map { $0.metrics.surfaceCompleteness }.reduce(0, +) / Double(relevantMetrics.count),
            noiseLevel: relevantMetrics.map { $0.metrics.noiseLevel }.reduce(0, +) / Double(relevantMetrics.count),
            featurePreservation: relevantMetrics.map { $0.metrics.featurePreservation }.reduce(0, +) / Double(relevantMetrics.count),
            curvatureAccuracy: relevantMetrics.map { $0.metrics.curvatureAccuracy }.reduce(0, +) / Double(relevantMetrics.count)
        )
    }
    
    func analyzeTrend() -> QualityTrend? {
        guard qualityHistory.count >= 3 else { return nil }
        
        let recentMetrics = qualityHistory.suffix(3).map { $0.metrics }
        let densityTrend = calculateTrend(recentMetrics.map { $0.pointDensity })
        let completenessTrend = calculateTrend(recentMetrics.map { $0.surfaceCompleteness })
        
        if densityTrend < -0.1 || completenessTrend < -0.1 {
            return .declining
        } else if densityTrend > 0.1 && completenessTrend > 0.1 {
            return .improving
        }
        
        return .stable
    }
    
    func shouldAdjustParameters() -> AdjustmentRecommendation? {
        guard let avgMetrics = getAverageMetrics(duration: 2.0) else { return nil }
        
        if avgMetrics.pointDensity < thresholds.minDensity {
            return .increaseDensity
        } else if avgMetrics.noiseLevel > thresholds.maxNoise {
            return .reduceNoise
        } else if avgMetrics.featurePreservation < thresholds.minFeaturePreservation {
            return .enhanceFeatures
        }
        
        return nil
    }
    
    private func calculateTrend(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<values.count {
            sum += values[i] - values[i-1]
        }
        return sum / Double(values.count - 1)
    }
}

struct QualityMetrics {
    let pointDensity: Double      // points/cm²
    let surfaceCompleteness: Double // percentage
    let noiseLevel: Double        // mm
    let featurePreservation: Double // percentage
    let curvatureAccuracy: Double // mm
}

struct QualityThresholds {
    let minDensity: Double
    let maxDensity: Double
    let minCompleteness: Double
    let maxNoise: Double
    let minFeaturePreservation: Double
    let minCurvatureAccuracy: Double
}

enum QualityTrend {
    case improving
    case stable
    case declining
}

enum AdjustmentRecommendation {
    case increaseDensity
    case reduceNoise
    case enhanceFeatures
}