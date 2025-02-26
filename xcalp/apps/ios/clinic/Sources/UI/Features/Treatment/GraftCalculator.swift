import Foundation
import Vision
import simd

public final class GraftCalculator {
    private let densityAnalyzer: DensityAnalyzer
    private let zoneOptimizer: ZoneOptimizer
    
    public init(
        densityAnalyzer: DensityAnalyzer = DensityAnalyzer(),
        zoneOptimizer: ZoneOptimizer = ZoneOptimizer()
    ) {
        self.densityAnalyzer = densityAnalyzer
        self.zoneOptimizer = zoneOptimizer
    }
    
    public func calculateGrafts(
        measurements: Measurements,
        preferences: GraftPreferences
    ) async throws -> GraftCalculation {
        // Analyze existing hair density in recipient area
        let existingDensity = try await densityAnalyzer.analyzeExistingDensity(
            area: measurements.recipientArea,
            preferences: preferences
        )
        
        // Calculate optimal distribution based on available donor area
        let distribution = try calculateDistribution(
            donorArea: measurements.donorArea,
            preferences: preferences
        )
        
        // Calculate total grafts needed
        let totalGrafts = try calculateTotalGrafts(
            recipientArea: measurements.recipientArea,
            targetDensity: preferences.targetDensity,
            existingDensity: existingDensity
        )
        
        // Optimize zones for graft placement
        let zones = try await zoneOptimizer.optimizeZones(
            totalGrafts: totalGrafts,
            distribution: distribution,
            measurements: measurements,
            preferences: preferences
        )
        
        return GraftCalculation(
            totalGrafts: totalGrafts,
            density: preferences.targetDensity,
            distribution: distribution,
            zones: zones
        )
    }
    
    private func calculateDistribution(
        donorArea: Float,
        preferences: GraftPreferences
    ) throws -> [GraftType: Int] {
        // Validate donor area
        guard donorArea > 0 else {
            throw GraftError.invalidArea("Donor area must be greater than 0")
        }
        
        // Calculate maximum available grafts from donor area
        let maxGrafts = Int(donorArea * preferences.maxDonorDensity)
        
        // Calculate distribution based on preferences
        var distribution: [GraftType: Int] = [:]
        var remainingGrafts = maxGrafts
        
        // Distribute grafts according to priority
        for type in preferences.graftTypePriorities {
            let percentage = preferences.typeDistribution[type] ?? 0
            let typeGrafts = Int(Float(maxGrafts) * percentage)
            distribution[type] = min(typeGrafts, remainingGrafts)
            remainingGrafts -= distribution[type] ?? 0
        }
        
        return distribution
    }
    
    private func calculateTotalGrafts(
        recipientArea: Float,
        targetDensity: Float,
        existingDensity: Float
    ) throws -> Int {
        // Validate inputs
        guard recipientArea > 0 else {
            throw GraftError.invalidArea("Recipient area must be greater than 0")
        }
        guard targetDensity > 0 else {
            throw GraftError.invalidDensity("Target density must be greater than 0")
        }
        guard existingDensity >= 0 else {
            throw GraftError.invalidDensity("Existing density cannot be negative")
        }
        
        // Calculate additional grafts needed
        let additionalDensity = max(0, targetDensity - existingDensity)
        return Int(recipientArea * additionalDensity)
    }
}

// MARK: - Supporting Types

public struct GraftPreferences {
    public let targetDensity: Float
    public let maxDonorDensity: Float
    public let typeDistribution: [GraftType: Float]
    public let graftTypePriorities: [GraftType]
    public let zonePreferences: [ZonePreference]
    
    public init(
        targetDensity: Float,
        maxDonorDensity: Float,
        typeDistribution: [GraftType: Float],
        graftTypePriorities: [GraftType],
        zonePreferences: [ZonePreference]
    ) {
        self.targetDensity = targetDensity
        self.maxDonorDensity = maxDonorDensity
        self.typeDistribution = typeDistribution
        self.graftTypePriorities = graftTypePriorities
        self.zonePreferences = zonePreferences
    }
}

public struct ZonePreference {
    public let name: String
    public let priority: GraftZone.Priority
    public let targetDensity: Float?
    public let typeDistribution: [GraftType: Float]?
    public let boundaries: [simd_float3]
    
    public init(
        name: String,
        priority: GraftZone.Priority,
        targetDensity: Float? = nil,
        typeDistribution: [GraftType: Float]? = nil,
        boundaries: [simd_float3]
    ) {
        self.name = name
        self.priority = priority
        self.targetDensity = targetDensity
        self.typeDistribution = typeDistribution
        self.boundaries = boundaries
    }
}

public enum GraftError: Error {
    case invalidArea(String)
    case invalidDensity(String)
    case insufficientDonorArea(String)
    case optimizationFailure(String)
    case densityAnalysisFailed(String)
}

// MARK: - Supporting Classes

public final class DensityAnalyzer {
    private let visionModel: VNHairAnalysisRequest
    
    public init() {
        self.visionModel = VNHairAnalysisRequest()
    }
    
    public func analyzeExistingDensity(
        area: Float,
        preferences: GraftPreferences
    ) async throws -> Float {
        guard area > 0 else {
            throw GraftError.invalidArea("Area must be greater than 0")
        }
        
        // Create vision request to analyze hair density
        let request = VNDetectHairDensityRequest { (request, error) in
            if let error = error {
                throw GraftError.densityAnalysisFailed(error.localizedDescription)
            }
            
            guard let results = request.results as? [VNHairDensityObservation] else {
                throw GraftError.densityAnalysisFailed("Invalid results format")
            }
            
            // Calculate average density from observations
            let totalDensity = results.reduce(0.0) { $0 + $1.density }
            return Float(totalDensity / Double(results.count))
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try request.perform([request])
                if let density = request.results?.first?.density {
                    continuation.resume(returning: Float(density))
                } else {
                    continuation.resume(throwing: GraftError.densityAnalysisFailed("No density data available"))
                }
            } catch {
                continuation.resume(throwing: GraftError.densityAnalysisFailed(error.localizedDescription))
            }
        }
    }
}

public final class ZoneOptimizer {
    public init() {}
    
    public func optimizeZones(
        totalGrafts: Int,
        distribution: [GraftType: Int],
        measurements: Measurements,
        preferences: GraftPreferences
    ) async throws -> [GraftZone] {
        var zones: [GraftZone] = []
        var remainingGrafts = totalGrafts
        
        // Sort zones by priority
        let sortedPreferences = preferences.zonePreferences.sorted { $0.priority.rawValue < $1.priority.rawValue }
        
        for zonePreference in sortedPreferences {
            let zoneArea = try calculateZoneArea(boundaries: zonePreference.boundaries)
            
            // Calculate zone-specific density
            let targetDensity = zonePreference.targetDensity ?? preferences.targetDensity
            let zoneGrafts = min(
                Int(zoneArea * targetDensity),
                remainingGrafts
            )
            
            // Calculate graft type distribution for this zone
            let zoneDistribution = zonePreference.typeDistribution ?? preferences.typeDistribution
            
            let zone = GraftZone(
                id: UUID(),
                name: zonePreference.name,
                area: zoneArea,
                density: targetDensity,
                distribution: zoneDistribution,
                priority: zonePreference.priority,
                boundaries: zonePreference.boundaries
            )
            
            zones.append(zone)
            remainingGrafts -= zoneGrafts
            
            if remainingGrafts <= 0 {
                break
            }
        }
        
        return zones
    }
    
    private func calculateZoneArea(boundaries: [simd_float3]) throws -> Float {
        guard boundaries.count >= 3 else {
            throw GraftError.invalidArea("Zone must have at least 3 boundary points")
        }
        
        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<boundaries.count {
            let j = (i + 1) % boundaries.count
            area += boundaries[i].x * boundaries[j].z
            area -= boundaries[j].x * boundaries[i].z
        }
        
        return abs(area) / 2.0
    }
}
