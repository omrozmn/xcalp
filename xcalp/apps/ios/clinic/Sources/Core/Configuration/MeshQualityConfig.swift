import Foundation
import simd

enum MeshQualityConfig {
    // Point cloud quality thresholds
    static let minimumPointDensity: Float = 100.0  // points per cubic meter
    static let maximumNoiseLevel: Float = 0.05     // meters
    static let minimumFeatureConfidence: Float = 0.7
    
    // Surface reconstruction thresholds
    static let minimumSurfaceCompleteness: Float = 0.95
    static let maximumHoleSize: Float = 0.02       // meters
    static let minimumFeaturePreservation: Float = 0.8
    
    // Mesh optimization thresholds
    static let maximumEdgeLength: Float = 0.05     // meters
    static let minimumEdgeLength: Float = 0.001    // meters
    static let maximumTriangleAspectRatio: Float = 10.0
    static let maximumDeviationFromOriginal: Float = 0.002 // meters
    
    // Data fusion thresholds
    static let maximumAlignmentError: Float = 0.005 // meters
    static let minimumOverlap: Float = 0.3
    static let maximumConfidenceDifference: Float = 0.3
    
    // Processing parameters
    struct ProcessingParameters {
        var octreeDepth: Int
        var samplesPerNode: Int
        var pointWeight: Float
        var smoothingFactor: Float
        var featurePreservationWeight: Float
        
        static let defaultLiDAR = ProcessingParameters(
            octreeDepth: 8,
            samplesPerNode: 1,
            pointWeight: 4.0,
            smoothingFactor: 0.5,
            featurePreservationWeight: 1.0
        )
        
        static let defaultPhotogrammetry = ProcessingParameters(
            octreeDepth: 9,
            samplesPerNode: 2,
            pointWeight: 5.0,
            smoothingFactor: 0.3,
            featurePreservationWeight: 1.2
        )
        
        static let highQuality = ProcessingParameters(
            octreeDepth: 10,
            samplesPerNode: 4,
            pointWeight: 6.0,
            smoothingFactor: 0.2,
            featurePreservationWeight: 1.5
        )
    }
    
    // Quality level presets
    enum QualityPreset {
        case draft
        case standard
        case highQuality
        
        var parameters: ProcessingParameters {
            switch self {
            case .draft:
                return ProcessingParameters(
                    octreeDepth: 7,
                    samplesPerNode: 1,
                    pointWeight: 3.0,
                    smoothingFactor: 0.7,
                    featurePreservationWeight: 0.8
                )
            case .standard:
                return ProcessingParameters.defaultLiDAR
            case .highQuality:
                return ProcessingParameters.highQuality
            }
        }
        
        var thresholds: QualityThresholds {
            switch self {
            case .draft:
                return QualityThresholds(
                    minimumPointDensity: 50.0,
                    maximumNoiseLevel: 0.1,
                    minimumSurfaceCompleteness: 0.85,
                    minimumFeaturePreservation: 0.6
                )
            case .standard:
                return QualityThresholds(
                    minimumPointDensity: minimumPointDensity,
                    maximumNoiseLevel: maximumNoiseLevel,
                    minimumSurfaceCompleteness: minimumSurfaceCompleteness,
                    minimumFeaturePreservation: minimumFeaturePreservation
                )
            case .highQuality:
                return QualityThresholds(
                    minimumPointDensity: 200.0,
                    maximumNoiseLevel: 0.03,
                    minimumSurfaceCompleteness: 0.98,
                    minimumFeaturePreservation: 0.9
                )
            }
        }
    }
    
    struct QualityThresholds {
        let minimumPointDensity: Float
        let maximumNoiseLevel: Float
        let minimumSurfaceCompleteness: Float
        let minimumFeaturePreservation: Float
        
        func validate(_ metrics: QualityMetrics) -> ValidationResult {
            var issues: [QualityIssue] = []
            
            if metrics.pointDensity < minimumPointDensity {
                issues.append(.insufficientDensity(
                    current: metrics.pointDensity,
                    required: minimumPointDensity
                ))
            }
            
            if metrics.noiseLevel > maximumNoiseLevel {
                issues.append(.excessiveNoise(
                    current: metrics.noiseLevel,
                    maximum: maximumNoiseLevel
                ))
            }
            
            if metrics.surfaceCompleteness < minimumSurfaceCompleteness {
                issues.append(.incompleteSurface(
                    current: metrics.surfaceCompleteness,
                    required: minimumSurfaceCompleteness
                ))
            }
            
            if metrics.featurePreservation < minimumFeaturePreservation {
                issues.append(.poorFeaturePreservation(
                    current: metrics.featurePreservation,
                    required: minimumFeaturePreservation
                ))
            }
            
            return ValidationResult(
                isValid: issues.isEmpty,
                issues: issues
            )
        }
    }
    
    struct ValidationResult {
        let isValid: Bool
        let issues: [QualityIssue]
    }
    
    enum QualityIssue {
        case insufficientDensity(current: Float, required: Float)
        case excessiveNoise(current: Float, maximum: Float)
        case incompleteSurface(current: Float, required: Float)
        case poorFeaturePreservation(current: Float, required: Float)
        
        var description: String {
            switch self {
            case .insufficientDensity(let current, let required):
                return "Point density too low: \(String(format: "%.1f", current)) (required: \(String(format: "%.1f", required)))"
            case .excessiveNoise(let current, let maximum):
                return "Noise level too high: \(String(format: "%.3f", current)) (maximum: \(String(format: "%.3f", maximum)))"
            case .incompleteSurface(let current, let required):
                return "Surface incomplete: \(String(format: "%.1f%%", current * 100)) (required: \(String(format: "%.1f%%", required * 100)))"
            case .poorFeaturePreservation(let current, let required):
                return "Poor feature preservation: \(String(format: "%.1f%%", current * 100)) (required: \(String(format: "%.1f%%", required * 100)))"
            }
        }
        
        var recommendation: String {
            switch self {
            case .insufficientDensity:
                return "Move closer to the surface or scan more thoroughly"
            case .excessiveNoise:
                return "Hold the device more steady and ensure good lighting"
            case .incompleteSurface:
                return "Ensure all areas are scanned from multiple angles"
            case .poorFeaturePreservation:
                return "Scan important features more carefully and maintain consistent distance"
            }
        }
    }
}