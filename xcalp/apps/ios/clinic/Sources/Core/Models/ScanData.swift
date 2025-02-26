import Foundation
import SceneKit
import simd

struct ScanData: Codable {
    let id: UUID
    let patientId: UUID
    let timestamp: Date
    let deviceInfo: DeviceInfo
    
    // Core scan data
    let mesh: Mesh
    let pointCloud: PointCloud
    let textureMap: TextureMap?
    
    // Quality metrics
    let accuracy: Float
    let pointDensity: Int
    let qualityScore: Float
    let lightingScore: Float
    let isCalibrated: Bool
    let lastCalibrationDate: Date?
    
    // Analysis state
    var textureAnalysisComplete: Bool
    var analysisResults: AnalysisResults?
    
    struct DeviceInfo: Codable {
        let model: String
        let os: String
        let hasTrueDepth: Bool
        let hasLiDAR: Bool
    }
    
    struct Mesh: Codable {
        let vertices: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
        let subMeshes: [SubMesh]
        
        struct SubMesh: Codable {
            let name: String
            let materialIndex: Int
            let startIndex: Int
            let indexCount: Int
        }
    }
    
    struct PointCloud: Codable {
        let points: [SIMD3<Float>]
        let colors: [SIMD4<UInt8>]?
        let confidence: [Float]?
    }
    
    struct TextureMap: Codable {
        let resolution: SIMD2<Int>
        let data: Data
        let format: PixelFormat
        
        enum PixelFormat: String, Codable {
            case rgba8Unorm
            case bgra8Unorm
            case rgb8Unorm
        }
    }
    
    struct AnalysisResults: Codable {
        let hairlineAnalysis: HairlineAnalysis
        let densityMap: DensityMap
        let textureAnalysis: TextureAnalysis
        let timestamp: Date
        
        struct HairlineAnalysis: Codable {
            let points: [SIMD2<Float>]
            let classification: String
            let symmetryScore: Float
        }
        
        struct DensityMap: Codable {
            let resolution: SIMD2<Int>
            let values: [Float]
            let average: Float
            let peak: Float
        }
        
        struct TextureAnalysis: Codable {
            let regions: [TextureRegion]
            let overallTexture: TextureMetrics
            
            struct TextureRegion: Codable {
                let bounds: Bounds
                let texture: TextureMetrics
                
                struct Bounds: Codable {
                    let min: SIMD2<Float>
                    let max: SIMD2<Float>
                }
            }
        }
    }
}

// MARK: - Mesh Processing Extensions

extension ScanData.Mesh {
    func toSCNGeometry() -> SCNGeometry {
        let vertexSource = SCNGeometrySource(
            vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        
        let normalSource = SCNGeometrySource(
            normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        
        let element = SCNGeometryElement(
            indices: indices,
            primitiveType: .triangles
        )
        
        return SCNGeometry(
            sources: [vertexSource, normalSource],
            elements: [element]
        )
    }
}