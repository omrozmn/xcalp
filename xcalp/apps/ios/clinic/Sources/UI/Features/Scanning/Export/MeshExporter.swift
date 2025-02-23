import Foundation
import Metal
import ModelIO
import simd

public enum MeshExportFormat {
    case obj
    case usdz
    case ply
    
    var contentType: String {
        switch self {
        case .obj: return "model/obj"
        case .usdz: return "model/vnd.usdz+zip"
        case .ply: return "model/ply"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .obj: return "obj"
        case .usdz: return "usdz"
        case .ply: return "ply"
        }
    }
}

public struct MeshExporter {
    public static func export(
        _ mesh: MeshProcessor.ProcessedMesh,
        format: MeshExportFormat
    ) throws -> Data {
        // Create MDLMesh from processed mesh
        let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!)
        
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 0,
            bufferIndex: 1
        )
        vertexDescriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: 0,
            bufferIndex: 2
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        vertexDescriptor.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        vertexDescriptor.layouts[2] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD2<Float>>.stride)
        
        let mdlMesh = MDLMesh(
            vertexBuffer: mesh.vertices,
            vertexCount: mesh.metrics.optimizedVertexCount,
            descriptor: vertexDescriptor,
            submeshes: [
                MDLSubmesh(
                    indexBuffer: mesh.indices,
                    indexCount: mesh.indices.length / MemoryLayout<UInt32>.size,
                    indexType: .uInt32,
                    geometryType: .triangles,
                    material: nil
                )
            ]
        )
        
        // Set vertex normals
        mdlMesh.vertexBuffers[1] = mesh.normals
        
        // Set UV coordinates
        mdlMesh.vertexBuffers[2] = mesh.uvs
        
        // Export to requested format
        let asset = MDLAsset()
        asset.add(mdlMesh)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        
        try asset.export(to: outputURL)
        let data = try Data(contentsOf: outputURL)
        try FileManager.default.removeItem(at: outputURL)
        
        return data
    }
    
    public static func createMetadata(
        for mesh: MeshProcessor.ProcessedMesh,
        format: MeshExportFormat
    ) -> [String: Any] {
        [
            "contentType": format.contentType,
            "vertexCount": mesh.metrics.optimizedVertexCount,
            "triangleCount": mesh.indices.length / (3 * MemoryLayout<UInt32>.size),
            "quality": [
                "vertexDensity": mesh.quality.vertexDensity,
                "surfaceSmoothness": mesh.quality.surfaceSmoothness,
                "normalConsistency": mesh.quality.normalConsistency
            ],
            "processingMetrics": [
                "originalVertexCount": mesh.metrics.originalVertexCount,
                "optimizedVertexCount": mesh.metrics.optimizedVertexCount,
                "processingTime": mesh.metrics.processingTime,
                "memoryUsage": mesh.metrics.memoryUsage
            ]
        ]
    }
}