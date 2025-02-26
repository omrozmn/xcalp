import Foundation

public struct QualityAssessment: Equatable {
    public let pointDensity: Float
    public let surfaceCompleteness: Double
    public let noiseLevel: Float
    public let featurePreservation: Float
    public let timestamp: Date
    public let lightingScore: Double
    public let motionScore: Double
    public let complexityScore: Double
    
    public var overallQuality: ScanningQuality {
        let thresholds = AppConfiguration.Performance.Scanning.self
        
        if pointDensity >= thresholds.minPointDensity &&
           surfaceCompleteness >= thresholds.minSurfaceCompleteness &&
           noiseLevel <= thresholds.maxNoiseLevel &&
           featurePreservation >= thresholds.minFeaturePreservation {
            return .high
        } else if pointDensity >= thresholds.minPointDensity * 0.7 &&
                  surfaceCompleteness >= thresholds.minSurfaceCompleteness * 0.7 &&
                  noiseLevel <= thresholds.maxNoiseLevel * 1.3 &&
                  featurePreservation >= thresholds.minFeaturePreservation * 0.7 {
            return .medium
        } else {
            return .low
        }
    }
    
    public var isAcceptable: Bool {
        overallQuality != .low
    }
    
    public init(
        pointDensity: Float,
        surfaceCompleteness: Double,
        noiseLevel: Float,
        featurePreservation: Float,
        timestamp: Date = Date(),
        lightingScore: Double = 1.0,
        motionScore: Double = 1.0,
        complexityScore: Double = 0.5
    ) {
        self.pointDensity = pointDensity
        self.surfaceCompleteness = surfaceCompleteness
        self.noiseLevel = noiseLevel
        self.featurePreservation = featurePreservation
        self.timestamp = timestamp
        self.lightingScore = lightingScore
        self.motionScore = motionScore
        self.complexityScore = complexityScore
    }
}

public struct QualityMeasurement: Equatable {
    public let timestamp: Date
    public let pointDensity: Float
    public let surfaceCompleteness: Double
    public let noiseLevel: Float
    public let featurePreservation: Float
    public let lightingScore: Double
    public let motionScore: Double
    public let complexityScore: Double
    
    public init(
        timestamp: Date = Date(),
        pointDensity: Float,
        surfaceCompleteness: Double,
        noiseLevel: Float,
        featurePreservation: Float,
        lightingScore: Double = 1.0,
        motionScore: Double = 1.0,
        complexityScore: Double = 0.5
    ) {
        self.timestamp = timestamp
        self.pointDensity = pointDensity
        self.surfaceCompleteness = surfaceCompleteness
        self.noiseLevel = noiseLevel
        self.featurePreservation = featurePreservation
        self.lightingScore = lightingScore
        self.motionScore = motionScore
        self.complexityScore = complexityScore
    }
}

public struct EnvironmentMetrics: Equatable {
    public let lightingLevel: Double
    public let motionStability: Double
    public let surfaceComplexity: Double
    
    public init(
        lightingLevel: Double,
        motionStability: Double,
        surfaceComplexity: Double
    ) {
        self.lightingLevel = lightingLevel
        self.motionStability = motionStability
        self.surfaceComplexity = surfaceComplexity
    }
}