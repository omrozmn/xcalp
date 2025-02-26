import Foundation
import ModelIO
import RealityKit

public enum ModelExportFormat {
    case usdz
    case obj
    case ply
    
    var fileExtension: String {
        switch self {
        case .usdz: return "usdz"
        case .obj: return "obj"
        case .ply: return "ply"
        }
    }
    
    var contentType: String {
        switch self {
        case .usdz: return "model/vnd.usdz+zip"
        case .obj: return "model/obj"
        case .ply: return "application/x-ply"
        }
    }
}

public class ModelExportHandler {
    private let meshProcessor: MeshProcessor
    
    init(meshProcessor: MeshProcessor) {
        self.meshProcessor = meshProcessor
    }
    
    func exportModel(_ mesh: MeshResource, to format: ModelExportFormat) throws -> Data {
        switch format {
        case .usdz:
            return try exportToUSDZ(mesh)
        case .obj:
            return try exportToOBJ(mesh)
        case .ply:
            return try exportToPLY(mesh)
        }
    }
    
    private func exportToUSDZ(_ mesh: MeshResource) throws -> Data {
        // RealityKit's native USDZ export
        let model = try ModelEntity(mesh: mesh)
        return try model.export(to: .usdz)
    }
    
    private func exportToOBJ(_ mesh: MeshResource) throws -> Data {
        let asset = try createMDLAsset(from: mesh)
        let allocator = MDLMeshBufferDataAllocator()
        
        guard let data = try? MDLAsset.exportObject(
            asset: asset,
            allocator: allocator,
            index: 0
        ) else {
            throw MeshProcessingError.exportFailed
        }
        
        return data
    }
    
    private func exportToPLY(_ mesh: MeshResource) throws -> Data {
        let asset = try createMDLAsset(from: mesh)
        let allocator = MDLMeshBufferDataAllocator()
        
        guard let data = try? MDLAsset.exportPLY(
            asset: asset,
            allocator: allocator,
            index: 0,
            preserveNormals: true
        ) else {
            throw MeshProcessingError.exportFailed
        }
        
        return data
    }
    
    private func createMDLAsset(from mesh: MeshResource) throws -> MDLAsset {
        let descriptor = try mesh.contents.descriptor.unbox()
        guard let positions = descriptor.positions?.contents.unbox() as? [SIMD3<Float>],
              let normals = descriptor.normals?.contents.unbox() as? [SIMD3<Float>] else {
            throw MeshProcessingError.invalidData
        }
        
        let vertexBuffer = MDLMeshBufferDataAllocator().newBuffer(
            withBytes: positions,
            length: MemoryLayout<SIMD3<Float>>.stride * positions.count,
            type: .vertex
        )
        
        let normalBuffer = MDLMeshBufferDataAllocator().newBuffer(
            withBytes: normals,
            length: MemoryLayout<SIMD3<Float>>.stride * normals.count,
            type: .vertex
        )
        
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.addAttribute(
            withName: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.addAttribute(
            withName: MDLVertexAttributeNormal,
            format: .float3,
            offset: 0,
            bufferIndex: 1
        )
        
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: positions.count,
            descriptor: vertexDescriptor,
            submeshes: []
        )
        
        mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributeNormal,
            asFormat: .float3,
            stride: MemoryLayout<SIMD3<Float>>.stride
        ).data = normalBuffer
        
        let asset = MDLAsset()
        asset.add(mesh)
        
        return asset
    }
}