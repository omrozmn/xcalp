import Foundation
import CoreML
import simd

public final class MLDensityPredictor {
    private let model: MLModel
    private let resolution = 100
    
    public init(model: MLModel) {
        self.model = model
    }
    
    public func analyzeDensity(_ scanData: Data) async throws -> DensityMap {
        // Prepare input data
        let input = try processScanData(scanData)
        
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
            regionalDensities: regionalDensities,
            confidence: confidence
        )
    }
    
    public func predictRegionalDensity(
        normals: [SIMD3<Float>],
        curvature: [[Float]]
    ) async throws -> Double {
        // Convert normals to ML input format
        let features = try normalsToDensityFeatures(
            normals,
            curvature: curvature
        )
        
        // Make prediction
        let prediction = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: [
            "meshData": features
        ]))
        
        guard let densityValue = prediction.featureValue(for: "densityMap")?.multiArrayValue else {
            throw PredictionError.invalidOutput
        }
        
        // Calculate average density from prediction
        var totalDensity: Double = 0
        var count = 0
        
        for i in 0..<densityValue.count {
            if let value = try? densityValue[i].doubleValue, value > 0 {
                totalDensity += value
                count += 1
            }
        }
        
        return count > 0 ? totalDensity / Double(count) : 0
    }
    
    private func processScanData(_ data: Data) throws -> MLMultiArray {
        let converter = MeshConverter()
        let mesh = try converter.convert(data)
        
        // Create MLMultiArray with shape [1, resolution, resolution, 3]
        let shape = [1, resolution, resolution, 3] as [NSNumber]
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        
        // Project mesh vertices to resolution x resolution grid
        for vertex in mesh.vertices {
            // Convert from [-1,1] to [0,resolution-1]
            let x = Int((vertex.x + 1) * Float(resolution - 1) / 2)
            let y = Int((vertex.y + 1) * Float(resolution - 1) / 2)
            
            if x >= 0 && x < resolution && y >= 0 && y < resolution {
                // Store x,y,z coordinates
                array[[0, y, x, 0] as [NSNumber]] = vertex.x as NSNumber
                array[[0, y, x, 1] as [NSNumber]] = vertex.y as NSNumber
                array[[0, y, x, 2] as [NSNumber]] = vertex.z as NSNumber
            }
        }
        
        return array
    }
    
    private func normalsToDensityFeatures(
        _ normals: [SIMD3<Float>],
        curvature: [[Float]]
    ) throws -> MLMultiArray {
        let shape = [1, resolution, resolution, 4] as [NSNumber]  // x,y,z normals + curvature
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        
        // Project normals to grid
        for (i, normal) in normals.enumerated() {
            let x = i % resolution
            let y = i / resolution
            
            if x < resolution && y < resolution {
                array[[0, y, x, 0] as [NSNumber]] = normal.x as NSNumber
                array[[0, y, x, 1] as [NSNumber]] = normal.y as NSNumber
                array[[0, y, x, 2] as [NSNumber]] = normal.z as NSNumber
                array[[0, y, x, 3] as [NSNumber]] = curvature[y][x] as NSNumber
            }
        }
        
        return array
    }
    
    private func calculateRegionalDensity(_ array: MLMultiArray, for region: String) -> Double {
        var totalDensity: Double = 0
        var sampledPoints = 0
        
        // Define region boundaries
        let bounds = getRegionBounds(region)
        
        for y in bounds.startY..<bounds.endY {
            for x in bounds.startX..<bounds.endX {
                if let density = try? array[[y, x] as [NSNumber]].doubleValue {
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

public struct DensityMap {
    public let averageDensity: Double
    public let regionalDensities: [String: Double]
    public let confidence: Double
}

private struct RegionBounds {
    let startX: Int
    let endX: Int
    let startY: Int
    let endY: Int
}