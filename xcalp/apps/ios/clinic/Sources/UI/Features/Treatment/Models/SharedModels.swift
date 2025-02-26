import Foundation 
import simd

public struct Measurements: Codable {
    public let totalArea: Float
    public let recipientArea: Float
    public let donorArea: Float
    public let scalpThickness: Float
    public let customMeasurements: [CustomMeasurement]
    
    public init(
        totalArea: Float,
        recipientArea: Float,
        donorArea: Float,
        scalpThickness: Float,
        customMeasurements: [CustomMeasurement]
    ) {
        self.totalArea = totalArea
        self.recipientArea = recipientArea
        self.donorArea = donorArea
        self.scalpThickness = scalpThickness
        self.customMeasurements = customMeasurements
    }
}

public enum GraftType: String, Codable {
    case single
    case double
    case triple
    case quadruple
}

public struct GraftZone: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let area: Float
    public let density: Float
    public let distribution: [GraftType: Float]
    public let priority: Priority
    public let boundaries: [SIMD3<Float>]
    
    public enum Priority: Int, Codable {
        case high = 0
        case medium = 1
        case low = 2
    }
}

public struct GraftCalculation: Codable {
    public let totalGrafts: Int
    public let density: Float
    public let distribution: [GraftType: Int]
    public let zones: [GraftZone]
}

public struct MeshData {
    public var vertices: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]
    
    public init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>] = [], indices: [UInt32] = []) {
        self.vertices = vertices
        self.normals = normals
        self.indices = indices
    }
}

public struct TextureData {
    public let pixelBuffer: CVPixelBuffer
    
    public init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

public struct ScanData {
    public let meshData: MeshData
    public let textureData: TextureData
    public let metadata: [String: Any]
}

public enum MeasurementError: Error {
    case invalidRegion(String)
    case calculationError(String)
}