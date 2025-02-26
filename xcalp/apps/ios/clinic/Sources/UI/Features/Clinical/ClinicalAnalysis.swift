import CoreML
import Foundation
import MetalKit

public struct DensityMap {
    let averageDensity: Double
    let regionalDensities: [String: Double]
    
    
    func hasUniformity() -> Bool {
        let values = Array(regionalDensities.values)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return variance < 0.1 // 10% variance threshold
    }
    
    func findLowDensityRegions() -> [(name: String, density: Double)]? {
        let sortedRegions = regionalDensities.sorted { $0.value < $1.value }
        let lowDensityThreshold = averageDensity * 0.7 // 70% of average
        
        let lowRegions = sortedRegions.filter { $0.value < lowDensityThreshold }
        return lowRegions.isEmpty ? nil : lowRegions.map { ($0.key, $0.value) }
    }
    
    func findOptimalDonorRegions() -> [(name: String, density: Double)]? {
        let sortedRegions = regionalDensities.sorted { $0.value > $1.value }
        let highDensityThreshold = averageDensity * 1.3 // 130% of average
        
        let optimalRegions = sortedRegions.filter { $0.value > highDensityThreshold }
        return optimalRegions.isEmpty ? nil : optimalRegions.map { ($0.key, $0.value) }
    }
}

private struct RegionBounds {
    let startX: Int
    let endX: Int
    let startY: Int
    let endY: Int
}

public final class MLDensityPredictor {
    private let model: MLModel
    private let resolution = 100
    
    
    public init(model: MLModel) {
        self.model = model
    }
    
    public func analyzeDensity(_ scanData: Data) async throws -> DensityMap {
        // Prepare input data
        let input = try await processScanData(scanData)
        
        // Make prediction
        let prediction = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: [
            "meshData": input
        ]))
        
        // Extract density information
        guard let densityArray = prediction.featureValue(for: "densityMap")?.multiArrayValue,
              let confidence = prediction.featureValue(for: "confidence")?.doubleValue else {
            throw PredictionError.invalidOutput
        }
        
        // Convert to density map format
        var regionalDensities: [String: Double] = [:]
        var totalDensity: Double = 0
        var validRegions = 0
        
        // Process density map by regions
        let regions = ["hairline", "crown", "leftTemple", "rightTemple", "midScalp"]
        for region in regions {
            let density = calculateRegionalDensity(densityArray, for: region)
            if density > 0 {
                regionalDensities[region] = density
                totalDensity += density
                validRegions += 1
            }
        }
        
        let averageDensity = validRegions > 0 ? totalDensity / Double(validRegions) : 0
        
        return DensityMap(
            averageDensity: averageDensity,
            regionalDensities: regionalDensities
        )
    }
    
    private func processScanData(_ data: Data) throws -> MLMultiArray {
        let shape = [resolution, resolution, 3] as [NSNumber]
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        
        // Convert scan data to normalized height map format
        let converter = MeshConverter()
        let mesh = try converter.convert(data)
        
        // Project mesh vertices to 2D grid
        for vertex in mesh.vertices {
            let x = Int((vertex.x + 1.0) * Float(resolution - 1) / 2.0)
            let y = Int((vertex.y + 1.0) * Float(resolution - 1) / 2.0)
            
            if x >= 0 && x < resolution && y >= 0 && y < resolution {
                // Store x, y, z coordinates
                array[[y, x, 0] as [NSNumber]] = vertex.x as NSNumber
                array[[y, x, 1] as [NSNumber]] = vertex.y as NSNumber
                array[[y, x, 2] as [NSNumber]] = vertex.z as NSNumber
            }
        }
        
        return array
    }
    
    private func calculateRegionalDensity(_ densityArray: MLMultiArray, for region: String) -> Double {
        var totalDensity: Double = 0
        var sampledPoints = 0
        
        let bounds = getRegionBounds(region)
        
        for y in bounds.startY..<bounds.endY {
            for x in bounds.startX..<bounds.endX {
                if let density = try? densityArray[[y, x] as [NSNumber]].doubleValue {
                    totalDensity += density
                    sampledPoints += 1
                }
            }
        }
        
        return sampledPoints > 0 ? totalDensity / Double(sampledPoints) : 0
    }
    
    private func getRegionBounds(_ region: String) -> RegionBounds {
        switch region {
        case "hairline":
            return RegionBounds(startX: 0, endX: resolution, startY: 0, endY: resolution / 4)
        case "crown":
            return RegionBounds(startX: resolution / 3, endX: 2 * resolution / 3, 
                              startY: resolution / 3, endY: 2 * resolution / 3)
        case "leftTemple":
            return RegionBounds(startX: 0, endX: resolution / 3, 
                              startY: 0, endY: resolution / 2)
        case "rightTemple":
            return RegionBounds(startX: 2 * resolution / 3, endX: resolution, 
                              startY: 0, endY: resolution / 2)
        case "midScalp":
            return RegionBounds(startX: resolution / 4, endX: 3 * resolution / 4, 
                              startY: resolution / 4, endY: 3 * resolution / 4)
        default:
            return RegionBounds(startX: 0, endX: resolution, startY: 0, endY: resolution)
        }
    }
}

public struct DensityAnalysis {
    public let averageDensity: Double
    public let regionalDensities: [String: Double]
    
    public let recommendations: [String]
    public let confidence: Double
}

// Handles clinical analysis of scanned data
public final class ClinicalAnalysis {
    public static let shared = ClinicalAnalysis()
    private let modelLoader = MLModelLoader.shared
    private let surfaceAnalyzer: SurfaceAnalyzer
    private let qualityValidator: ScanQualityValidator
    private let graftOptimizer: GraftPlacementOptimizer
    private let edgeCaseHandler: EdgeCaseHandler
    
    private init() {
        do {
            self.surfaceAnalyzer = try SurfaceAnalyzer()
        } catch {
            fatalError("Failed to initialize SurfaceAnalyzer: \(error)")
        }
        self.qualityValidator = ScanQualityValidator()
        self.graftOptimizer = GraftPlacementOptimizer()
        self.edgeCaseHandler = EdgeCaseHandler()
        
        // Preload models in background
        Task {
            await preloadModels()
        }
    }
    
    private func preloadModels() async {
        await modelLoader.preloadModels([
            "HairDensityAnalyzer",
            "HairGrowthPatternAnalyzer"
        ])
    }
    
    public func analyzeScan(_ data: Data, ethnicity: String? = nil) async throws -> ClinicalAnalysisResult {
        // Validate scan quality first
        guard try await validateScanQuality(data) else {
            throw AnalysisError.insufficientScanQuality
        }
        
        // Analyze surface features and growth patterns
        let surfaceData = try await surfaceAnalyzer.analyzeSurface(data, ethnicity: ethnicity)
        
        // Analyze density distribution
        let densityAnalysis = try await analyzeDensity(surfaceData)
        
        // Generate treatment recommendations
        let recommendations = generateRecommendations(
            density: densityAnalysis,
            surfaceData: surfaceData
        )
        
        return ClinicalAnalysisResult(
            surfaceData: surfaceData,
            densityAnalysis: densityAnalysis,
            recommendations: recommendations,
            quality: try await calculateQualityMetrics(data)
        )
    }
    
    public func calculateGraftPlan(
        scanData: Data,
        targetDensity: Double,
        preserveExisting: Bool = true,
        ethnicity: String? = nil
    ) async throws -> GraftPlan {
        // Analyze current state
        let analysisResult = try await analyzeScan(scanData, ethnicity: ethnicity)
        
        // Calculate required grafts
        let graftPlan = try await graftOptimizer.optimizeGraftPlacements(
            surfaceData: analysisResult.surfaceData,
            densityAnalysis: analysisResult.densityAnalysis,
            targetDensity: targetDensity,
            preserveExisting: preserveExisting,
            ethnicity: ethnicity
        )
        
        // Handle edge cases in graft placement
        let refinedPlan = handleEdgeCases(
            plan: graftPlan,
            analysis: analysisResult,
            ethnicity: ethnicity
        )
        
        return refinedPlan
    }
    
    private func analyzeDensity(_ surfaceData: SurfaceData) async throws -> DensityAnalysis {
        // Load ML model
        let model = try await modelLoader.loadModel(named: "HairDensityAnalyzer")
        let densityPredictor = MLDensityPredictor(model: model)
        
        // Analyze each region
        var regionalDensities: [String: Double] = [:]
        var totalArea: Double = 0
        var weightedDensity: Double = 0
        
        for (region, data) in surfaceData.regions {
            let area = calculateRegionArea(data.boundaryPoints)
            let density = try await densityPredictor.predictRegionalDensity(
                normals: data.surfaceNormals,
                curvature: surfaceData.metrics.curvatureMap
            )
            
            regionalDensities[region] = density
            totalArea += area
            weightedDensity += density * area
        }
        
        let averageDensity = totalArea > 0 ? weightedDensity / totalArea : 0
        
        return DensityAnalysis(
            averageDensity: averageDensity,
            regionalDensities: regionalDensities,
            recommendations: generateDensityRecommendations(regionalDensities),
            confidence: calculateAnalysisConfidence(surfaceData)
        )
    }
    
    private func calculateRegionArea(_ points: [SIMD3<Float>]) -> Double {
        // Project points to 2D and calculate area using shoelace formula
        var area: Double = 0
        let count = points.count
        
        for i in 0..<count {
            let j = (i + 1) % count
            area += Double(points[i].x * points[j].y - points[j].x * points[i].y)
        }
        
        return abs(area) / 2.0
    }
    
    private func generateDensityRecommendations(_ densities: [String: Double]) -> [String] {
        var recommendations: [String] = []
        
        // Calculate density thresholds
        let lowDensityThreshold = 40.0  // hairs/cm²
        let optimalDensityThreshold = 65.0  // hairs/cm²
        
        // Identify problem areas
        let lowDensityRegions = densities.filter { $0.value < lowDensityThreshold }
        if !lowDensityRegions.isEmpty {
            recommendations.append("Priority treatment areas: \(lowDensityRegions.keys.joined(separator: ", "))")
        }
        
        // Calculate overall density distribution
        let avgDensity = densities.values.reduce(0, +) / Double(densities.count)
        let variance = densities.values.map { pow($0 - avgDensity, 2) }.reduce(0, +) / Double(densities.count)
        
        if variance > 100 {
            recommendations.append("Significant density variation detected. Consider gradual density matching.")
        }
        
        // Add specific recommendations based on patterns
        if let crownDensity = densities["crown"], crownDensity < lowDensityThreshold {
            recommendations.append("Crown area requires attention. Consider concentrated graft placement.")
        }
        
        return recommendations
    }
    
    private func calculateAnalysisConfidence(_ surfaceData: SurfaceData) -> Double {
        // Combine multiple confidence factors
        let metrics = [
            Double(surfaceData.metrics.quality.normalConsistency),
            Double(surfaceData.metrics.quality.triangleQuality),
            surfaceData.regions.values.map { Double($0.growthPattern.significance) }.reduce(0, +) /
                Double(surfaceData.regions.count)
        ]
        
        return metrics.reduce(0, +) / Double(metrics.count)
    }
    
    private func handleEdgeCases(
        plan: GraftPlan,
        analysis: ClinicalAnalysisResult,
        ethnicity: String?
    ) -> GraftPlan {
        var refinedDirections = plan.directions
        
        // Handle irregular patterns
        let refinedPatterns = edgeCaseHandler.handleIrregularPatterns(
            in: analysis.surfaceData,
            ethnicity: ethnicity
        )
        
        // Apply refinements to graft directions
        for (region, pattern) in refinedPatterns {
            refinedDirections = refinedDirections.map { direction in
                if direction.region == region {
                    return Direction(angle: pattern.direction, region: region)
                }
                return direction
            }
        }
        
        return GraftPlan(
            totalGrafts: plan.totalGrafts,
            regions: plan.regions,
            directions: refinedDirections
        )
    }
    
    private func calculateQualityMetrics(_ data: Data) async throws -> QualityMetrics {
        let validationResult = try await qualityValidator.validateScan(data)
        return QualityMetrics(
            overallQuality: validationResult.meetsQualityThresholds ? .good : .poor,
            coverage: validationResult.metrics.coverage,
            resolution: validationResult.metrics.vertexDensity,
            confidence: validationResult.metrics.qualityScore
        )
    }
}

public struct ClinicalAnalysisResult {
    public let surfaceData: SurfaceData
    public let densityAnalysis: DensityAnalysis
    public let recommendations: [String]
    public let quality: QualityMetrics
}

public struct QualityMetrics {
    public let overallQuality: Quality
    public let coverage: Float
    
    public let resolution: Float
    public let confidence: Float
    
    public enum Quality {
        case poor
        case acceptable
        case good
    }
}

public struct GraftPlan {
    public let totalGrafts: Int
    public let regions: [String: Int]
    
    public let directions: [Direction]
    
    public struct Direction {
        public let angle: Double
        public let region: String
    }
}

enum AnalysisError: Error {
    case insufficientScanQuality
    case invalidRegion
    case calculationError
}

import Foundation
import CoreML
import Metal

/// Main coordinator class for clinical hair analysis
final class ClinicalAnalysis {
    static let shared = ClinicalAnalysis()
    
    private let surfaceAnalyzer: SurfaceAnalyzer
    private let qualityValidator: ScanQualityValidator
    private let regionDetector: RegionDetector
    private let curvatureAnalyzer: CurvatureAnalyzer
    private let edgeCaseHandler: EdgeCaseHandler
    private let modelLoader: MLModelLoader
    private let calibrationManager: CalibrationManager
    
    private init() {
        // Initialize components
        do {
            self.surfaceAnalyzer = try SurfaceAnalyzer()
            self.qualityValidator = ScanQualityValidator()
            self.regionDetector = try RegionDetector()
            self.curvatureAnalyzer = try CurvatureAnalyzer()
            self.edgeCaseHandler = EdgeCaseHandler()
            self.modelLoader = .shared
            self.calibrationManager = .shared
        } catch {
            fatalError("Failed to initialize ClinicalAnalysis: \(error)")
        }
    }
    
    func analyzeScan(
        _ data: Data,
        ethnicity: String? = nil,
        targetDensity: Double? = nil
    ) async throws -> AnalysisResult {
        // 1. Validate scan quality
        let qualityAssessment = try await qualityValidator.validateScanQuality(data)
        guard qualityAssessment.meetsMinimumRequirements else {
            throw AnalysisError.insufficientQuality(qualityAssessment.recommendations)
        }
        
        // 2. Analyze surface features
        async let surfaceData = surfaceAnalyzer.analyzeSurface(data, ethnicity: ethnicity)
        
        // 3. Analyze density using ML model
        async let densityAnalysis = analyzeDensity(data)
        
        // Wait for parallel computations
        let (surface, density) = try await (surfaceData, densityAnalysis)
        
        // 4. Handle edge cases and irregularities
        let refinedPatterns = edgeCaseHandler.handleIrregularPatterns(
            in: surface,
            ethnicity: ethnicity
        )
        
        // 5. Calculate graft plan if target density provided
        let graftPlan = try targetDensity.map { target in
            try await calculateGraftPlan(
                scanData: data,
                targetDensity: target,
                currentDensity: density.averageDensity,
                regions: surface.regions
            )
        }
        
        // 6. Generate recommendations
        let recommendations = generateRecommendations(
            surface: surface,
            density: density,
            graftPlan: graftPlan,
            ethnicity: ethnicity
        )
        
        return AnalysisResult(
            surfaceData: surface,
            densityAnalysis: density,
            refinedPatterns: refinedPatterns,
            graftPlan: graftPlan,
            recommendations: recommendations,
            quality: QualityMetrics(
                coverage: qualityAssessment.metrics.coverage,
                resolution: Float(surface.metrics.quality.vertexDensity),
                confidence: Double(surface.metrics.quality.normalConsistency)
            )
        )
    }
    
    func validateScanQuality(_ data: Data) async throws -> Bool {
        let assessment = try await qualityValidator.validateScanQuality(data)
        return assessment.meetsMinimumRequirements
    }
    
    func analyzeDensity(_ data: Data) async throws -> DensityAnalysis {
        // Load ML model
        let model = try await modelLoader.loadModel(named: "HairDensityAnalyzer")
        let predictor = MLDensityPredictor(model: model)
        
        // Perform density analysis
        let densityMap = try await predictor.analyzeDensity(data)
        
        // Apply ethnicity-specific calibration if needed
        let calibratedDensities = densityMap.regionalDensities.mapValues { density in
            calibrationManager.calibrateDensity(
                density: density,
                region: "default",
                ethnicity: "default"
            )
        }
        
        return DensityAnalysis(
            averageDensity: densityMap.averageDensity,
            regionalDensities: calibratedDensities,
            confidence: densityMap.confidence
        )
    }
    
    func calculateGraftPlan(
        scanData: Data,
        targetDensity: Double,
        currentDensity: Double,
        regions: [String: RegionData]
    ) async throws -> GraftPlan {
        // Calculate required grafts based on density difference
        let totalArea = regions.values.reduce(0.0) { sum, region in
            sum + Double(region.metrics.area)
        }
        
        let densityDifference = max(0, targetDensity - currentDensity)
        let totalGrafts = Int(densityDifference * totalArea)
        
        // Allocate grafts to regions based on area and priority
        var regionalGrafts: [String: Int] = [:]
        var graftDirections: [Direction] = []
        
        for (region, data) in regions {
            let regionArea = Double(data.metrics.area)
            let regionPriority = getRegionPriority(region)
            let regionGrafts = Int(Double(totalGrafts) * (regionArea / totalArea) * regionPriority)
            
            regionalGrafts[region] = regionGrafts
            
            // Generate graft directions based on natural growth pattern
            let pattern = data.growthPattern
            graftDirections.append(contentsOf: generateGraftDirections(
                count: regionGrafts,
                baseDirection: pattern.direction,
                variance: pattern.variance
            ))
        }
        
        return GraftPlan(
            totalGrafts: totalGrafts,
            regions: regionalGrafts,
            directions: graftDirections
        )
    }
    
    private func generateRecommendations(
        surface: SurfaceData,
        density: DensityAnalysis,
        graftPlan: GraftPlan?,
        ethnicity: String?
    ) -> [ClinicalRecommendation] {
        var recommendations: [ClinicalRecommendation] = []
        
        // Analyze density distribution
        if let densityIssues = analyzeDensityDistribution(density) {
            recommendations.append(contentsOf: densityIssues)
        }
        
        // Analyze growth patterns
        for (region, data) in surface.regions {
            if data.growthPattern.significance < 0.7 {
                recommendations.append(.improveGrowthPattern(region: region))
            }
        }
        
        // Add graft-specific recommendations
        if let plan = graftPlan {
            recommendations.append(contentsOf: analyzeGraftPlan(plan))
        }
        
        return recommendations
    }
    
    private func getRegionPriority(_ region: String) -> Double {
        switch region.lowercased() {
        case "hairline": return 1.2
        case "crown": return 1.1
        case "temples": return 1.0
        case "midscalp": return 0.9
        default: return 1.0
        }
    }
    
    private func analyzeDensityDistribution(_ density: DensityAnalysis) -> [ClinicalRecommendation]? {
        var recommendations: [ClinicalRecommendation] = []
        
        // Check for significant density variations
        let avgDensity = density.averageDensity
        for (region, density) in density.regionalDensities {
            if density < avgDensity * 0.7 {
                recommendations.append(.lowDensity(region: region))
            }
        }
        
        return recommendations.isEmpty ? nil : recommendations
    }
    
    private func analyzeGraftPlan(_ plan: GraftPlan) -> [ClinicalRecommendation] {
        var recommendations: [ClinicalRecommendation] = []
        
        // Check graft distribution
        if plan.totalGrafts > 3000 {
            recommendations.append(.multipleSessionsRecommended)
        }
        
        // Analyze regional distribution
        for (region, grafts) in plan.regions {
            if grafts > 1500 {
                recommendations.append(.highGraftDensity(region: region))
            }
        }
        
        return recommendations
    }
    
    private func generateGraftDirections(
        count: Int,
        baseDirection: SIMD3<Float>,
        variance: Float
    ) -> [Direction] {
        var directions: [Direction] = []
        
        for _ in 0..<count {
            // Add controlled randomness to base direction
            let randomAngle = Float.random(in: -variance...variance)
            let rotatedDirection = rotateVector(
                baseDirection,
                around: SIMD3<Float>(0, 0, 1),
                by: randomAngle
            )
            
            directions.append(Direction(
                vector: rotatedDirection,
                confidence: 1.0 - abs(randomAngle) / variance
            ))
        }
        
        return directions
    }
    
    private func rotateVector(
        _ vector: SIMD3<Float>,
        around axis: SIMD3<Float>,
        by angle: Float
    ) -> SIMD3<Float> {
        let cosA = cos(angle)
        let sinA = sin(angle)
        
        return vector * cosA +
               cross(axis, vector) * sinA +
               axis * dot(axis, vector) * (1 - cosA)
    }
}

struct AnalysisResult {
    let surfaceData: SurfaceData
    let densityAnalysis: DensityAnalysis
    let refinedPatterns: [String: RefinedPattern]
    let graftPlan: GraftPlan?
    let recommendations: [ClinicalRecommendation]
    let quality: QualityMetrics
}

struct DensityAnalysis {
    let averageDensity: Double
    let regionalDensities: [String: Double]
    let confidence: Double
}

struct Direction {
    let vector: SIMD3<Float>
    let confidence: Float
}

enum ClinicalRecommendation {
    case lowDensity(region: String)
    case improveGrowthPattern(region: String)
    case highGraftDensity(region: String)
    case multipleSessionsRecommended
    
    var description: String {
        switch self {
        case .lowDensity(let region):
            return "Low density detected in \(region) region"
        case .improveGrowthPattern(let region):
            return "Irregular growth pattern in \(region) region"
        case .highGraftDensity(let region):
            return "High graft density planned for \(region) region"
        case .multipleSessionsRecommended:
            return "Multiple treatment sessions recommended"
        }
    }
}

struct QualityMetrics {
    let coverage: Float
    let resolution: Float
    let confidence: Double
}

enum AnalysisError: Error {
    case insufficientQuality([ScanRecommendation])
    case processingFailed(String)
    case invalidData
}
