import Foundation
import simd

protocol ScanDataProvider {
    func getCurrentScan() -> ScanData?
    func saveScan(_ scan: ScanData) throws
    func getScanHistory() -> [ScanData]
}

protocol ScanQualityValidating {
    func validateQuality(_ metrics: QualityMetrics) -> Bool
    func getQualityReport() -> QualityReport
}

struct ScanData: Codable {
    let id: UUID
    let timestamp: Date
    let patientId: String
    let scanType: ScanType
    let qualityMetrics: QualityMetrics
    let pointCloud: PointCloudData
    let processingMetadata: ProcessingMetadata
    
    enum ScanType: String, Codable {
        case lidar
        case photogrammetry
        case hybrid
    }
}

struct PointCloudData: Codable {
    let points: [simd_float3]
    let normals: [simd_float3]?
    let confidence: [Float]?
    let boundingBox: BoundingBox
    
    struct BoundingBox: Codable {
        let min: simd_float3
        let max: simd_float3
    }
}

struct ProcessingMetadata: Codable {
    let processingDuration: TimeInterval
    let algorithmVersion: String
    let qualityChecks: [QualityCheck]
    let fallbacksTriggered: [FallbackEvent]
    
    struct QualityCheck: Codable {
        let timestamp: Date
        let checkType: String
        let passed: Bool
        let metrics: [String: Float]
    }
    
    struct FallbackEvent: Codable {
        let timestamp: Date
        let fromMode: ScanData.ScanType
        let toMode: ScanData.ScanType
        let reason: String
    }
}

struct QualityReport: Codable {
    let overallQuality: Float
    let pointDensityMap: [String: Float]
    let surfaceCompleteness: Float
    let symmetryScore: Float
    let noiseLevel: Float
    let recommendations: [String]
    
    var isAcceptable: Bool {
        return overallQuality >= 0.85 && // 85% minimum overall quality
               surfaceCompleteness >= 0.98 && // 98% minimum completeness
               noiseLevel <= 0.1 // 0.1mm maximum noise
    }
}

extension simd_float3: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        self.init(x: x, y: y, z: z)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(z)
    }
}

extension QualityMetrics {
    func generateReport() -> QualityReport {
        let overallQuality = calculateOverallQuality()
        let densityMap = generateDensityMap()
        
        return QualityReport(
            overallQuality: overallQuality,
            pointDensityMap: densityMap,
            surfaceCompleteness: surfaceCompleteness,
            symmetryScore: calculateSymmetryScore(),
            noiseLevel: noiseLevel,
            recommendations: generateRecommendations()
        )
    }
    
    private func calculateOverallQuality() -> Float {
        // Weight different metrics to calculate overall quality
        let weights: [Float] = [0.3, 0.3, 0.2, 0.2] // Weights must sum to 1
        let metrics: [Float] = [
            pointDensity / 750.0, // Normalize to 0-1 range
            surfaceCompleteness / 100.0,
            (1.0 - noiseLevel / 0.1), // Inverse and normalize
            featurePreservation / 100.0
        ]
        
        return zip(metrics, weights)
            .map { $0 * $1 }
            .reduce(0, +)
    }
    
    private func generateDensityMap() -> [String: Float] {
        // Placeholder for actual density mapping logic
        return [
            "frontal": pointDensity,
            "crown": pointDensity,
            "vertex": pointDensity,
            "temporal_right": pointDensity,
            "temporal_left": pointDensity,
            "occipital": pointDensity
        ]
    }
    
    private func calculateSymmetryScore() -> Float {
        // Placeholder for symmetry calculation
        return 1.0
    }
    
    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []
        
        if pointDensity < 500 {
            recommendations.append("Increase scan density for better detail")
        }
        
        if surfaceCompleteness < 98 {
            recommendations.append("Complete additional scans to cover missing areas")
        }
        
        if noiseLevel > 0.1 {
            recommendations.append("Reduce environmental noise and maintain steady scanning motion")
        }
        
        if featurePreservation < 95 {
            recommendations.append("Ensure proper scanning distance and lighting conditions")
        }
        
        return recommendations
    }
}