import Foundation
import simd

public struct TreatmentPlan: Identifiable, Equatable, Codable {
    public let id: UUID
    public let scanId: UUID
    public let patientId: UUID
    public let createdAt: Date
    public let measurements: Measurements
    public let graftCalculation: GraftCalculation
    public let densityMap: DensityMap
    public let directionPlan: DirectionPlan
    public let notes: String?
    public let status: Status
    
    public init(
        id: UUID = UUID(),
        scanId: UUID,
        patientId: UUID,
        createdAt: Date = Date(),
        measurements: Measurements,
        graftCalculation: GraftCalculation,
        densityMap: DensityMap,
        directionPlan: DirectionPlan,
        notes: String? = nil,
        status: Status = .draft
    ) {
        self.id = id
        self.scanId = scanId
        self.patientId = patientId
        self.createdAt = createdAt
        self.measurements = measurements
        self.graftCalculation = graftCalculation
        self.densityMap = densityMap
        self.directionPlan = directionPlan
        self.notes = notes
        self.status = status
    }
    
    public enum Status: String, Codable {
        case draft
        case inReview
        case approved
        case inProgress
        case completed
        case archived
    }
}

public struct Measurements: Equatable, Codable {
    public let totalArea: Float // in cm²
    public let recipientArea: Float // in cm²
    public let donorArea: Float // in cm²
    public let scalpThickness: Float // in mm
    public let customMeasurements: [CustomMeasurement]
    
    public init(
        totalArea: Float,
        recipientArea: Float,
        donorArea: Float,
        scalpThickness: Float,
        customMeasurements: [CustomMeasurement] = []
    ) {
        self.totalArea = totalArea
        self.recipientArea = recipientArea
        self.donorArea = donorArea
        self.scalpThickness = scalpThickness
        self.customMeasurements = customMeasurements
    }
}

public struct CustomMeasurement: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let value: Float
    public let unit: String
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        name: String,
        value: Float,
        unit: String,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.notes = notes
    }
}

public struct GraftCalculation: Equatable, Codable {
    public let totalGrafts: Int
    public let density: Float // grafts per cm²
    public let distribution: [GraftType: Int]
    public let zones: [GraftZone]
    
    public init(
        totalGrafts: Int,
        density: Float,
        distribution: [GraftType: Int],
        zones: [GraftZone]
    ) {
        self.totalGrafts = totalGrafts
        self.density = density
        self.distribution = distribution
        self.zones = zones
    }
}

public enum GraftType: String, Codable {
    case single
    case double
    case triple
    case quadruple
}

public struct GraftZone: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let area: Float // in cm²
    public let density: Float // grafts per cm²
    public let distribution: [GraftType: Float] // percentage of each type
    public let priority: Priority
    public let boundaries: [simd_float3]
    
    public init(
        id: UUID = UUID(),
        name: String,
        area: Float,
        density: Float,
        distribution: [GraftType: Float],
        priority: Priority,
        boundaries: [simd_float3]
    ) {
        self.id = id
        self.name = name
        self.area = area
        self.density = density
        self.distribution = distribution
        self.priority = priority
        self.boundaries = boundaries
    }
    
    public enum Priority: Int, Codable {
        case low = 0
        case medium = 1
        case high = 2
    }
}

public struct DensityMap: Equatable, Codable {
    public let resolution: Float // points per cm²
    public let densityValues: [[Float]] // 2D array of density values
    public let maxDensity: Float
    public let minDensity: Float
    public let regions: [DensityRegion]
    
    public init(
        resolution: Float,
        densityValues: [[Float]],
        maxDensity: Float,
        minDensity: Float,
        regions: [DensityRegion]
    ) {
        self.resolution = resolution
        self.densityValues = densityValues
        self.maxDensity = maxDensity
        self.minDensity = minDensity
        self.regions = regions
    }
}

public struct DensityRegion: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let boundaries: [simd_float3]
    public let averageDensity: Float
    public let targetDensity: Float
    
    public init(
        id: UUID = UUID(),
        name: String,
        boundaries: [simd_float3],
        averageDensity: Float,
        targetDensity: Float
    ) {
        self.id = id
        self.name = name
        self.boundaries = boundaries
        self.averageDensity = averageDensity
        self.targetDensity = targetDensity
    }
}

public struct DirectionPlan: Equatable, Codable {
    public let naturalDirections: [DirectionVector]
    public let plannedDirections: [DirectionVector]
    public let regions: [DirectionRegion]
    
    public init(
        naturalDirections: [DirectionVector],
        plannedDirections: [DirectionVector],
        regions: [DirectionRegion]
    ) {
        self.naturalDirections = naturalDirections
        self.plannedDirections = plannedDirections
        self.regions = regions
    }
}

public struct DirectionVector: Identifiable, Equatable, Codable {
    public let id: UUID
    public let position: simd_float3
    public let direction: simd_float3
    public let confidence: Float
    
    public init(
        id: UUID = UUID(),
        position: simd_float3,
        direction: simd_float3,
        confidence: Float
    ) {
        self.id = id
        self.position = position
        self.direction = direction
        self.confidence = confidence
    }
}

public struct DirectionRegion: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let boundaries: [simd_float3]
    public let dominantDirection: simd_float3
    public let variability: Float // 0-1, how much directions vary in this region
    
    public init(
        id: UUID = UUID(),
        name: String,
        boundaries: [simd_float3],
        dominantDirection: simd_float3,
        variability: Float
    ) {
        self.id = id
        self.name = name
        self.boundaries = boundaries
        self.dominantDirection = dominantDirection
        self.variability = variability
    }
}
