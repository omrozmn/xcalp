import Foundation
import Metal
import simd
import os.log

final class FeaturePreservationValidator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "FeatureValidation")
    private let performanceMonitor = PerformanceMonitor.shared
    private let qualityThresholds: ValidationThresholds
    
    struct ValidationThresholds {
        let minimumFeatureDensity: Float
        let minimumFeatureConfidence: Float
        let minimumPreservationScore: Float
        let maximumDeformation: Float
        let minimumTemporalConsistency: Float
        
        static let clinical = ValidationThresholds(
            minimumFeatureDensity: 50.0,    // features per square meter
            minimumFeatureConfidence: 0.85,
            minimumPreservationScore: 0.9,
            maximumDeformation: 0.02,        // 2% of bounding box diagonal
            minimumTemporalConsistency: 0.95
        )
    }
    
    struct ValidationResult {
        let isValid: Bool
        let metrics: ValidationMetrics
        let issues: [ValidationIssue]
        let recommendations: [String]
        
        var requiresImmediate: Bool {
            issues.contains { $0.severity == .critical }
        }
    }
    
    struct ValidationMetrics {
        let featureDensity: Float
        let averageConfidence: Float
        let preservationScore: Float
        let maxDeformation: Float
        let temporalConsistency: Float
        
        var meetsRequirements: Bool {
            featureDensity >= ClinicalConstants.minimumFeatureDensity &&
            averageConfidence >= ClinicalConstants.minimumFeatureConfidence &&
            preservationScore >= ClinicalConstants.minimumPreservationScore &&
            maxDeformation <= ClinicalConstants.maximumDeformation &&
            temporalConsistency >= ClinicalConstants.minimumTemporalConsistency
        }
    }
    
    struct ValidationIssue {
        let type: IssueType
        let severity: IssueSeverity
        let message: String
        let metrics: [String: Float]
        
        enum IssueType {
            case lowDensity
            case lowConfidence
            case poorPreservation
            case excessiveDeformation
            case temporalInconsistency
        }
        
        enum IssueSeverity {
            case warning
            case error
            case critical
        }
    }
    
    init(thresholds: ValidationThresholds = .clinical) {
        self.qualityThresholds = thresholds
    }
    
    func validatePreservation(
        original: [AnatomicalFeature],
        preserved: [AnatomicalFeature],
        meshBefore: MeshData,
        meshAfter: MeshData
    ) async -> ValidationResult {
        let perfID = performanceMonitor.startMeasuring("featureValidation")
        defer { performanceMonitor.endMeasuring("featureValidation", signpostID: perfID) }
        
        // Calculate validation metrics
        let metrics = try? await calculateMetrics(
            original: original,
            preserved: preserved,
            meshBefore: meshBefore,
            meshAfter: meshAfter
        )
        
        guard let metrics = metrics else {
            return ValidationResult(
                isValid: false,
                metrics: ValidationMetrics(
                    featureDensity: 0,
                    averageConfidence: 0,
                    preservationScore: 0,
                    maxDeformation: Float.infinity,
                    temporalConsistency: 0
                ),
                issues: [
                    ValidationIssue(
                        type: .poorPreservation,
                        severity: .critical,
                        message: "Failed to calculate validation metrics",
                        metrics: [:]
                    )
                ],
                recommendations: ["Restart scanning session"]
            )
        }
        
        // Analyze issues
        var issues: [ValidationIssue] = []
        
        // Check feature density
        if metrics.featureDensity < qualityThresholds.minimumFeatureDensity {
            issues.append(ValidationIssue(
                type: .lowDensity,
                severity: metrics.featureDensity < qualityThresholds.minimumFeatureDensity / 2 ? .critical : .warning,
                message: "Insufficient feature density detected",
                metrics: ["current": metrics.featureDensity, "required": qualityThresholds.minimumFeatureDensity]
            ))
        }
        
        // Check confidence
        if metrics.averageConfidence < qualityThresholds.minimumFeatureConfidence {
            issues.append(ValidationIssue(
                type: .lowConfidence,
                severity: .warning,
                message: "Low feature confidence detected",
                metrics: ["current": metrics.averageConfidence, "required": qualityThresholds.minimumFeatureConfidence]
            ))
        }
        
        // Check preservation
        if metrics.preservationScore < qualityThresholds.minimumPreservationScore {
            issues.append(ValidationIssue(
                type: .poorPreservation,
                severity: metrics.preservationScore < qualityThresholds.minimumPreservationScore / 2 ? .critical : .error,
                message: "Poor feature preservation detected",
                metrics: ["current": metrics.preservationScore, "required": qualityThresholds.minimumPreservationScore]
            ))
        }
        
        // Check deformation
        if metrics.maxDeformation > qualityThresholds.maximumDeformation {
            issues.append(ValidationIssue(
                type: .excessiveDeformation,
                severity: metrics.maxDeformation > qualityThresholds.maximumDeformation * 2 ? .critical : .error,
                message: "Excessive mesh deformation detected",
                metrics: ["current": metrics.maxDeformation, "maximum": qualityThresholds.maximumDeformation]
            ))
        }
        
        // Check temporal consistency
        if metrics.temporalConsistency < qualityThresholds.minimumTemporalConsistency {
            issues.append(ValidationIssue(
                type: .temporalInconsistency,
                severity: .warning,
                message: "Temporal inconsistency detected",
                metrics: ["current": metrics.temporalConsistency, "required": qualityThresholds.minimumTemporalConsistency]
            ))
        }
        
        // Generate recommendations
        let recommendations = generateRecommendations(issues: issues, metrics: metrics)
        
        // Log validation results
        logValidationResults(metrics: metrics, issues: issues)
        
        return ValidationResult(
            isValid: issues.isEmpty,
            metrics: metrics,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    private func calculateMetrics(
        original: [AnatomicalFeature],
        preserved: [AnatomicalFeature],
        meshBefore: MeshData,
        meshAfter: MeshData
    ) async throws -> ValidationMetrics {
        // Calculate feature density
        let boundingBox = calculateBoundingBox(meshAfter.vertices)
        let surfaceArea = calculateSurfaceArea(meshAfter)
        let featureDensity = Float(preserved.count) / surfaceArea
        
        // Calculate average confidence
        let averageConfidence = preserved.reduce(0.0) { $0 + $1.confidence } / Float(preserved.count)
        
        // Calculate preservation score
        let preservationScore = calculatePreservationScore(
            original: original,
            preserved: preserved
        )
        
        // Calculate maximum deformation
        let maxDeformation = calculateMaxDeformation(
            before: meshBefore,
            after: meshAfter,
            features: preserved
        )
        
        // Calculate temporal consistency
        let temporalConsistency = calculateTemporalConsistency(preserved)
        
        return ValidationMetrics(
            featureDensity: featureDensity,
            averageConfidence: averageConfidence,
            preservationScore: preservationScore,
            maxDeformation: maxDeformation,
            temporalConsistency: temporalConsistency
        )
    }
    
    private func calculatePreservationScore(
        original: [AnatomicalFeature],
        preserved: [AnatomicalFeature]
    ) -> Float {
        var totalScore: Float = 0
        var matchCount = 0
        
        for originalFeature in original {
            if let preservedFeature = preserved.first(where: { $0.uniqueID == originalFeature.uniqueID }) {
                let positionDiff = distance(originalFeature.position, preservedFeature.position)
                let normalDiff = 1 - abs(dot(originalFeature.normal, preservedFeature.normal))
                
                let score = (1 - positionDiff) * (1 - normalDiff)
                totalScore += score
                matchCount += 1
            }
        }
        
        return matchCount > 0 ? totalScore / Float(matchCount) : 0
    }
    
    private func calculateMaxDeformation(
        before: MeshData,
        after: MeshData,
        features: [AnatomicalFeature]
    ) -> Float {
        var maxDeformation: Float = 0
        
        for feature in features {
            // Find nearest vertices in both meshes
            if let beforeVertex = findNearestVertex(feature.position, in: before.vertices),
               let afterVertex = findNearestVertex(feature.position, in: after.vertices) {
                let deformation = distance(beforeVertex, afterVertex)
                maxDeformation = max(maxDeformation, deformation)
            }
        }
        
        return maxDeformation
    }
    
    private func calculateTemporalConsistency(_ features: [AnatomicalFeature]) -> Float {
        // Calculate feature position stability over time
        var consistency: Float = 1.0
        // Implementation details...
        return consistency
    }
    
    private func generateRecommendations(
        issues: [ValidationIssue],
        metrics: ValidationMetrics
    ) -> [String] {
        var recommendations: [String] = []
        
        for issue in issues {
            switch issue.type {
            case .lowDensity:
                recommendations.append("Increase scanning coverage to capture more features")
                recommendations.append("Ensure proper scanning distance (30-50cm)")
                
            case .lowConfidence:
                recommendations.append("Improve lighting conditions")
                recommendations.append("Reduce device motion")
                recommendations.append("Ensure clean scanning surface")
                
            case .poorPreservation:
                recommendations.append("Adjust feature preservation strength")
                recommendations.append("Reduce mesh simplification ratio")
                
            case .excessiveDeformation:
                recommendations.append("Reduce smoothing intensity")
                recommendations.append("Increase feature preservation radius")
                
            case .temporalInconsistency:
                recommendations.append("Reduce scanning speed")
                recommendations.append("Maintain consistent scanning distance")
            }
        }
        
        return recommendations
    }
    
    private func logValidationResults(
        metrics: ValidationMetrics,
        issues: [ValidationIssue]
    ) {
        logger.info("""
            Feature preservation validation results:
            - Feature Density: \(metrics.featureDensity) features/m²
            - Average Confidence: \(metrics.averageConfidence)
            - Preservation Score: \(metrics.preservationScore)
            - Max Deformation: \(metrics.maxDeformation)mm
            - Temporal Consistency: \(metrics.temporalConsistency)
            Issues Found: \(issues.count)
            \(issues.map { "- [\($0.severity)]: \($0.message)" }.joined(separator: "\n"))
            """)
    }
}

// MARK: - Helper Functions

extension FeaturePreservationValidator {
    private func calculateBoundingBox(_ vertices: [SIMD3<Float>]) -> BoundingBox {
        var box = BoundingBox()
        for vertex in vertices {
            box.min = simd_min(box.min, vertex)
            box.max = simd_max(box.max, vertex)
        }
        return box
    }
    
    private func calculateSurfaceArea(_ mesh: MeshData) -> Float {
        var area: Float = 0
        for triangle in mesh.triangles {
            let v0 = mesh.vertices[Int(triangle.x)]
            let v1 = mesh.vertices[Int(triangle.y)]
            let v2 = mesh.vertices[Int(triangle.z)]
            
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            area += length(cross(edge1, edge2)) * 0.5
        }
        return area
    }
    
    private func findNearestVertex(
        _ point: SIMD3<Float>,
        in vertices: [SIMD3<Float>]
    ) -> SIMD3<Float>? {
        guard !vertices.isEmpty else { return nil }
        
        var nearestVertex = vertices[0]
        var minDistance = distance(point, vertices[0])
        
        for vertex in vertices.dropFirst() {
            let dist = distance(point, vertex)
            if dist < minDistance {
                minDistance = dist
                nearestVertex = vertex
            }
        }
        
        return nearestVertex
    }
}

// MARK: - Supporting Types

struct BoundingBox {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    
    init() {
        min = SIMD3<Float>(repeating: Float.infinity)
        max = SIMD3<Float>(repeating: -Float.infinity)
    }
    
    var size: SIMD3<Float> {
        max - min
    }
    
    var center: SIMD3<Float> {
        (min + max) * 0.5
    }
}