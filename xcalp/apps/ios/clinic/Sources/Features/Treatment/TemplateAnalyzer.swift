import Foundation
import CoreML

public struct TemplateAnalyzer {
    public struct ComparisonResult {
        public let templates: [TreatmentTemplate]
        public let metrics: [ComparisonMetric]
        public let recommendations: [String]
        public let riskFactors: [RiskFactor]
        
        public struct ComparisonMetric: Identifiable {
            public let id: UUID
            public let name: String
            public let values: [UUID: Double] // Template ID to value mapping
            public let weight: Double
            public let optimalRange: ClosedRange<Double>
            public let description: String
        }
        
        public struct RiskFactor: Identifiable {
            public let id: UUID
            public let severity: Severity
            public let description: String
            public let affectedTemplates: [UUID] // Template IDs
            public let mitigation: String
            
            public enum Severity: String {
                case low, medium, high
            }
        }
    }
    
    public func compareTemplates(_ templates: [TreatmentTemplate], for patient: PatientData) -> ComparisonResult {
        var metrics: [ComparisonResult.ComparisonMetric] = []
        var riskFactors: [ComparisonResult.RiskFactor] = []
        
        // Analyze density distribution
        metrics.append(analyzeDensityDistribution(templates))
        
        // Analyze growth timeline
        metrics.append(analyzeGrowthTimeline(templates, patient: patient))
        
        // Analyze naturalness
        metrics.append(analyzeNaturalness(templates))
        
        // Analyze resource requirements
        metrics.append(analyzeResourceRequirements(templates))
        
        // Analyze risk factors
        riskFactors = identifyRiskFactors(templates, patient: patient)
        
        // Generate recommendations based on analysis
        let recommendations = generateRecommendations(
            templates: templates,
            metrics: metrics,
            riskFactors: riskFactors,
            patient: patient
        )
        
        return ComparisonResult(
            templates: templates,
            metrics: metrics,
            recommendations: recommendations,
            riskFactors: riskFactors
        )
    }
    
    private func analyzeDensityDistribution(_ templates: [TreatmentTemplate]) -> ComparisonResult.ComparisonMetric {
        var values: [UUID: Double] = [:]
        
        for template in templates {
            let densityScore = calculateDensityScore(template)
            values[template.id] = densityScore
        }
        
        return ComparisonResult.ComparisonMetric(
            id: UUID(),
            name: "Density Distribution",
            values: values,
            weight: 0.3,
            optimalRange: 0.7...1.0,
            description: "Evaluates the effectiveness of graft distribution and density patterns"
        )
    }
    
    private func analyzeGrowthTimeline(_ templates: [TreatmentTemplate], patient: PatientData) -> ComparisonResult.ComparisonMetric {
        var values: [UUID: Double] = [:]
        
        for template in templates {
            let timelineScore = calculateTimelineScore(template, patient: patient)
            values[template.id] = timelineScore
        }
        
        return ComparisonResult.ComparisonMetric(
            id: UUID(),
            name: "Growth Timeline",
            values: values,
            weight: 0.25,
            optimalRange: 0.8...1.0,
            description: "Predicts the expected timeline for visible results"
        )
    }
    
    private func analyzeNaturalness(_ templates: [TreatmentTemplate]) -> ComparisonResult.ComparisonMetric {
        var values: [UUID: Double] = [:]
        
        for template in templates {
            let naturalnessScore = calculateNaturalnessScore(template)
            values[template.id] = naturalnessScore
        }
        
        return ComparisonResult.ComparisonMetric(
            id: UUID(),
            name: "Natural Appearance",
            values: values,
            weight: 0.25,
            optimalRange: 0.75...1.0,
            description: "Evaluates how natural the final result will appear"
        )
    }
    
    private func analyzeResourceRequirements(_ templates: [TreatmentTemplate]) -> ComparisonResult.ComparisonMetric {
        var values: [UUID: Double] = [:]
        
        for template in templates {
            let resourceScore = calculateResourceScore(template)
            values[template.id] = resourceScore
        }
        
        return ComparisonResult.ComparisonMetric(
            id: UUID(),
            name: "Resource Efficiency",
            values: values,
            weight: 0.2,
            optimalRange: 0.6...1.0,
            description: "Assesses the efficiency of graft usage and procedure time"
        )
    }
    
    private func identifyRiskFactors(_ templates: [TreatmentTemplate], patient: PatientData) -> [ComparisonResult.RiskFactor] {
        var riskFactors: [ComparisonResult.RiskFactor] = []
        
        // Check age-related risks
        if patient.age > 60 {
            let affectedTemplates = templates.filter { $0.parameters.targetDensity > 45 }.map { $0.id }
            if !affectedTemplates.isEmpty {
                riskFactors.append(ComparisonResult.RiskFactor(
                    id: UUID(),
                    severity: .medium,
                    description: "Higher age may affect healing and growth rate",
                    affectedTemplates: affectedTemplates,
                    mitigation: "Consider reducing target density and extending timeline expectations"
                ))
            }
        }
        
        // Check health-related risks
        if patient.hasDiabetes {
            let affectedTemplates = templates.filter { $0.parameters.graftSpacing < 0.8 }.map { $0.id }
            if !affectedTemplates.isEmpty {
                riskFactors.append(ComparisonResult.RiskFactor(
                    id: UUID(),
                    severity: .high,
                    description: "Diabetes may affect healing and graft survival",
                    affectedTemplates: affectedTemplates,
                    mitigation: "Increase graft spacing and implement strict post-procedure monitoring"
                ))
            }
        }
        
        // Check scalp condition risks
        if patient.scalpHealthScore < 0.7 {
            let affectedTemplates = templates.filter { $0.parameters.targetDensity > 40 }.map { $0.id }
            if !affectedTemplates.isEmpty {
                riskFactors.append(ComparisonResult.RiskFactor(
                    id: UUID(),
                    severity: .high,
                    description: "Suboptimal scalp condition may affect graft survival",
                    affectedTemplates: affectedTemplates,
                    mitigation: "Recommend scalp treatment before procedure and reduce target density"
                ))
            }
        }
        
        return riskFactors
    }
    
    private func generateRecommendations(
        templates: [TreatmentTemplate],
        metrics: [ComparisonResult.ComparisonMetric],
        riskFactors: [ComparisonResult.RiskFactor],
        patient: PatientData
    ) -> [String] {
        var recommendations: [String] = []
        
        // Find best performing template
        if let bestTemplate = findBestTemplate(templates, metrics: metrics) {
            recommendations.append("Template '\(bestTemplate.name)' shows the most promising overall results based on analysis.")
        }
        
        // Risk-based recommendations
        if !riskFactors.isEmpty {
            let highRisks = riskFactors.filter { $0.severity == .high }
            if !highRisks.isEmpty {
                recommendations.append("Consider addressing \(highRisks.count) high-risk factors before proceeding.")
            }
        }
        
        // Age-specific recommendations
        if patient.age > 50 {
            recommendations.append("Consider extended recovery timeline due to age-related healing factors.")
        }
        
        // Health-based recommendations
        if patient.scalpHealthScore < 0.8 {
            recommendations.append("Recommend scalp treatment program before procedure to improve outcomes.")
        }
        
        return recommendations
    }
    
    private func calculateDensityScore(_ template: TreatmentTemplate) -> Double {
        let targetDensity = template.parameters.targetDensity
        let graftSpacing = template.parameters.graftSpacing
        
        // Normalize density score based on optimal ranges
        let densityFactor = min(1.0, targetDensity / 50.0) // Assuming 50 grafts/cm² is maximum
        let spacingFactor = min(1.0, graftSpacing / 1.0) // Assuming 1.0mm is optimal spacing
        
        return (densityFactor * 0.6 + spacingFactor * 0.4)
    }
    
    private func calculateTimelineScore(_ template: TreatmentTemplate, patient: PatientData) -> Double {
        var baseScore = 1.0
        
        // Adjust for age
        if patient.age > 50 {
            baseScore *= 0.9
        }
        
        // Adjust for health factors
        if patient.hasDiabetes {
            baseScore *= 0.8
        }
        
        if patient.isSmokingHistory {
            baseScore *= 0.85
        }
        
        // Adjust for template parameters
        let densityFactor = min(1.0, template.parameters.targetDensity / 45.0)
        baseScore *= densityFactor
        
        return baseScore
    }
    
    private func calculateNaturalnessScore(_ template: TreatmentTemplate) -> Double {
        let angleVariation = template.parameters.angleVariation
        let naturalness = template.parameters.naturalness
        
        // Normalize angle variation (15-25 degrees considered optimal)
        let angleFactor = if angleVariation < 15 {
            angleVariation / 15.0
        } else if angleVariation > 25 {
            1.0 - ((angleVariation - 25.0) / 15.0)
        } else {
            1.0
        }
        
        return (angleFactor * 0.4 + naturalness * 0.6)
    }
    
    private func calculateResourceScore(_ template: TreatmentTemplate) -> Double {
        let efficiency = 1.0 - (abs(template.parameters.graftSpacing - 0.8) / 0.8)
        let complexity = template.regions.count
        let complexityFactor = 1.0 - (Double(complexity - 1) * 0.1)
        
        return (efficiency * 0.7 + complexityFactor * 0.3)
    }
    
    private func findBestTemplate(_ templates: [TreatmentTemplate], metrics: [ComparisonResult.ComparisonMetric]) -> TreatmentTemplate? {
        var scores: [UUID: Double] = [:]
        
        // Calculate weighted scores for each template
        for template in templates {
            var totalScore = 0.0
            var totalWeight = 0.0
            
            for metric in metrics {
                if let value = metric.values[template.id] {
                    totalScore += value * metric.weight
                    totalWeight += metric.weight
                }
            }
            
            if totalWeight > 0 {
                scores[template.id] = totalScore / totalWeight
            }
        }
        
        // Find template with highest score
        return templates.max { a, b in
            (scores[a.id] ?? 0) < (scores[b.id] ?? 0)
        }
    }
}