import ComposableArchitecture
import CoreML
import SwiftUI

struct TemplateRecommendationsView: View {
    let store: StoreOf<TemplateList>
    let onTemplateSelected: (TreatmentTemplate) -> Void
    
    @State private var targetDensity: Double = 40.0
    @State private var regionCount: Int = 2
    @State private var treatmentTime: TimeInterval = 60 * 60 // 1 hour default
    @State private var recommendations: [TemplateRecommendationEngine.Recommendation] = []
    @State private var isLoading = false
    
    @Dependency(\.templateRecommendationEngine) private var recommendationEngine
    
    var body: some View {
        List {
            Section("Preferences") {
                VStack(alignment: .leading) {
                    Text("Target Density (grafts/cm²)")
                    Slider(value: $targetDensity, in: 20...60, step: 1)
                    Text("\(Int(targetDensity))")
                }
                
                Stepper("Number of Regions: \(regionCount)", value: $regionCount, in: 1...5)
                
                VStack(alignment: .leading) {
                    Text("Estimated Treatment Time")
                    Picker("Duration", selection: $treatmentTime) {
                        Text("30 minutes").tag(TimeInterval(30 * 60))
                        Text("1 hour").tag(TimeInterval(60 * 60))
                        Text("1.5 hours").tag(TimeInterval(90 * 60))
                        Text("2 hours").tag(TimeInterval(120 * 60))
                    }
                }
            }
            
            Section("Recommendations") {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if recommendations.isEmpty {
                    Text("No recommendations available")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recommendations, id: \.template.id) { recommendation in
                        RecommendationRow(recommendation: recommendation)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onTemplateSelected(recommendation.template)
                            }
                    }
                }
            }
        }
        .task(id: targetDensity) {
            await loadRecommendations()
        }
        .task(id: regionCount) {
            await loadRecommendations()
        }
        .task(id: treatmentTime) {
            await loadRecommendations()
        }
        .navigationTitle("Template Recommendations")
    }
    
    private func loadRecommendations() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            recommendations = try await recommendationEngine.getRecommendations(
                targetDensity: targetDensity,
                regionCount: regionCount,
                treatmentTime: treatmentTime
            )
        } catch {
            // Handle error
            recommendations = []
            print("Error loading recommendations: \(error.localizedDescription)")
        }
    }
}

private struct RecommendationRow: View {
    let recommendation: TemplateRecommendationEngine.Recommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recommendation.template.name)
                .font(.headline)
            
            Text(recommendation.template.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                ProgressView(value: recommendation.confidence, total: 1.0)
                    .tint(confidenceColor)
                Text("\(Int(recommendation.confidence * 100))% Match")
                    .font(.caption)
                    .foregroundColor(confidenceColor)
            }
            
            Text(recommendation.reason)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var confidenceColor: Color {
        switch recommendation.confidence {
        case 0.8...:
            return .green
        case 0.6..<0.8:
            return .blue
        default:
            return .orange
        }
    }
}

public struct TreatmentTemplate: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let description: String
    public let version: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let parameters: TemplateParameters
    public let regions: [TreatmentRegion]
    public let author: String
    public let isCustom: Bool
    public let parentTemplateId: UUID?
    public var versionHistory: [VersionHistoryEntry]
    public var compatibilityScore: Double?
    public var simulationResults: SimulationResults?
    
    public struct VersionHistoryEntry: Identifiable, Equatable {
        public let id: UUID
        public let version: Int
        public let timestamp: Date
        public let author: String
        public let changes: [String]
    }
    
    public struct SimulationResults: Equatable {
        public var expectedGrowthRate: Double
        public var coverageEstimate: Double
        public var naturalnessPrediction: Double
        public var timelineMarkers: [TimelineMarker]
        
        public struct TimelineMarker: Identifiable, Equatable {
            public let id: UUID
            public let month: Int
            public let expectedProgress: Double
            public let description: String
        }
    }
    
    public mutating func simulate(patientData: PatientData) -> SimulationResults {
        let results = SimulationResults(
            expectedGrowthRate: calculateGrowthRate(patientData),
            coverageEstimate: estimateCoverage(patientData),
            naturalnessPrediction: predictNaturalness(patientData),
            timelineMarkers: generateTimeline(patientData)
        )
        self.simulationResults = results
        return results
    }
    
    public mutating func createNewVersion(changes: [String], author: String) {
        let entry = VersionHistoryEntry(
            id: UUID(),
            version: version + 1,
            timestamp: Date(),
            author: author,
            changes: changes
        )
        versionHistory.append(entry)
    }
    
    private func calculateGrowthRate(_ data: PatientData) -> Double {
        // Calculate expected growth rate based on patient factors
        let baseRate = 0.7 // Base success rate
        var modifiers: Double = 1.0
        
        // Age factor
        modifiers *= max(0.8, 1.0 - Double(max(0, data.age - 40)) * 0.01)
        
        // Health factors
        if data.hasDiabetes { modifiers *= 0.9 }
        if data.isSmokingHistory { modifiers *= 0.85 }
        
        // Scalp condition
        modifiers *= data.scalpHealthScore
        
        return baseRate * modifiers
    }
    
    private func estimateCoverage(_ data: PatientData) -> Double {
        // Estimate final coverage based on template parameters and patient data
        let baseCoverage = parameters.targetDensity / 60.0 // Normalize to 0-1
        let regionFactor = calculateRegionCoverageFactor()
        let healthFactor = data.scalpHealthScore
        
        return baseCoverage * regionFactor * healthFactor
    }
    
    private func predictNaturalness(_ data: PatientData) -> Double {
        // Predict how natural the result will look
        var score = parameters.naturalness
        
        // Adjust based on angle variation
        score *= 0.5 + (parameters.angleVariation / 30.0) * 0.5
        
        // Adjust based on graft spacing
        let spacingFactor = (parameters.graftSpacing - 0.5) / 1.0
        score *= 0.7 + spacingFactor * 0.3
        
        return score
    }
    
    private func generateTimeline(_ data: PatientData) -> [TimelineMarker.ID: TimelineMarker] {
        let markers = [
            TimelineMarker(
                id: UUID(),
                month: 1,
                expectedProgress: 0.1,
                description: "Initial healing phase"
            ),
            TimelineMarker(
                id: UUID(),
                month: 3,
                expectedProgress: 0.3,
                description: "Early growth phase"
            ),
            TimelineMarker(
                id: UUID(),
                month: 6,
                expectedProgress: 0.6,
                description: "Main growth phase"
            ),
            TimelineMarker(
                id: UUID(),
                month: 12,
                expectedProgress: 0.9,
                description: "Final results visible"
            )
        ]
        return markers
    }
    
    private func calculateRegionCoverageFactor() -> Double {
        let totalArea = regions.reduce(0.0) { $0 + $1.area }
        let weightedCoverage = regions.reduce(0.0) { $0 + ($1.area / totalArea) * ($1.parameters.density / 60.0) }
        return weightedCoverage
    }
}

public struct TemplateRecommendationEngine {
    public struct RecommendationResult {
        let template: TreatmentTemplate
        let score: Double
        let matchingFactors: [String]
        let considerations: [String]
    }
    
    // Core recommendation factors
    private let ageWeight: Double = 0.2
    private let scalpHealthWeight: Double = 0.3
    private let hairTypeWeight: Double = 0.25
    private let densityWeight: Double = 0.25
    
    public func recommendTemplates(
        for patient: PatientData,
        from templates: [TreatmentTemplate]
    ) -> [RecommendationResult] {
        // Calculate scores for each template
        let results = templates.map { template in
            let (score, factors, considerations) = evaluateTemplate(template, for: patient)
            return RecommendationResult(
                template: template,
                score: score,
                matchingFactors: factors,
                considerations: considerations
            )
        }
        
        // Sort by score and return top matches
        return results
            .sorted { $0.score > $1.score }
            .filter { $0.score >= 0.7 } // Only return good matches
    }
    
    private func evaluateTemplate(
        _ template: TreatmentTemplate,
        for patient: PatientData
    ) -> (score: Double, factors: [String], considerations: [String]) {
        var score = 0.0
        var matchingFactors: [String] = []
        var considerations: [String] = []
        
        // Age compatibility
        let ageScore = calculateAgeCompatibility(patient.age, template)
        score += ageScore * ageWeight
        if ageScore > 0.8 {
            matchingFactors.append("Age-appropriate template design")
        } else if ageScore < 0.6 {
            considerations.append("Age may affect treatment outcomes")
        }
        
        // Scalp health compatibility
        let healthScore = calculateScalpHealthCompatibility(patient.scalpHealthScore, template)
        score += healthScore * scalpHealthWeight
        if healthScore > 0.8 {
            matchingFactors.append("Suitable for current scalp condition")
        } else if healthScore < 0.6 {
            considerations.append("May need scalp preparation before treatment")
        }
        
        // Hair type compatibility
        let hairScore = calculateHairTypeCompatibility(patient.hairType, template)
        score += hairScore * hairTypeWeight
        if hairScore > 0.8 {
            matchingFactors.append("Optimal for hair type and characteristics")
        } else if hairScore < 0.6 {
            considerations.append("Template may need adjustment for hair type")
        }
        
        // Density requirements
        let densityScore = calculateDensityCompatibility(patient.donorDensity, template)
        score += densityScore * densityWeight
        if densityScore > 0.8 {
            matchingFactors.append("Matches donor area capacity")
        } else if densityScore < 0.6 {
            considerations.append("May need to adjust target density")
        }
        
        // Additional medical considerations
        if patient.hasDiabetes {
            considerations.append("Consider healing time adjustments")
            score *= 0.9
        }
        
        if patient.isSmokingHistory {
            considerations.append("May affect growth rate")
            score *= 0.95
        }
        
        return (score, matchingFactors, considerations)
    }
    
    private func calculateAgeCompatibility(_ age: Int, _ template: TreatmentTemplate) -> Double {
        let optimalAge = 30...50
        let acceptable = 20...60
        
        if optimalAge.contains(age) {
            return 1.0
        } else if acceptable.contains(age) {
            return 0.8
        } else {
            return 0.6
        }
    }
    
    private func calculateScalpHealthCompatibility(_ health: Double, _ template: TreatmentTemplate) -> Double {
        // Direct correlation with scalp health score
        health
    }
    
    private func calculateHairTypeCompatibility(_ hairType: HairType, _ template: TreatmentTemplate) -> Double {
        // Match hair type characteristics with template parameters
        let angleMatchScore = matchAngleRequirements(hairType, template.parameters.angleVariation)
        let spacingMatchScore = matchSpacingRequirements(hairType, template.parameters.graftSpacing)
        
        return (angleMatchScore + spacingMatchScore) / 2.0
    }
    
    private func calculateDensityCompatibility(_ donorDensity: Double, _ template: TreatmentTemplate) -> Double {
        // Check if donor density can support template requirements
        let requiredDensity = template.parameters.targetDensity
        let ratio = donorDensity / requiredDensity
        
        if ratio >= 2.0 { // Plenty of donor hair
            return 1.0
        } else if ratio >= 1.5 {
            return 0.9
        } else if ratio >= 1.0 {
            return 0.7
        } else {
            return 0.5
        }
    }
    
    private func matchAngleRequirements(_ hairType: HairType, _ angleVariation: Double) -> Double {
        switch hairType {
        case .straight:
            return angleVariation <= 20 ? 1.0 : 0.8
        case .wavy:
            return angleVariation <= 25 ? 1.0 : 0.9
        case .curly:
            return angleVariation <= 30 ? 1.0 : 0.7
        }
    }
    
    private func matchSpacingRequirements(_ hairType: HairType, _ spacing: Double) -> Double {
        switch hairType {
        case .straight:
            return spacing >= 0.8 ? 1.0 : 0.8
        case .wavy:
            return spacing >= 0.7 ? 1.0 : 0.9
        case .curly:
            return spacing >= 0.6 ? 1.0 : 0.7
        }
    }
}
