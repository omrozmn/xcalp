import Foundation
import simd
import ModelIO

public final class MeshConverter {
    public init() {}
    
    public func convert(_ data: Data) throws -> MeshData {
        // Create temporary file to load mesh data
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_mesh.obj")
        try data.write(to: tempURL)
        let asset = MDLAsset(url: tempURL)
        guard let mesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh else {
            throw ConversionError.invalidMeshData
        }
        
        let vertexCount = mesh.vertexCount
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        
        // Extract vertex positions
        guard let vertexBuffer = mesh.vertexBuffers.first else {
            throw ConversionError.missingVertexData
        }
        
        let vertexStride = vertexBuffer.length / vertexCount
        let vertexPointer = vertexBuffer.map().bytes.bindMemory(to: Float.self, capacity: vertexCount * vertexStride)
        
        for i in 0..<vertexCount {
            let offset = i * vertexStride / MemoryLayout<Float>.stride
            let x = vertexPointer[offset]
            let y = vertexPointer[offset + 1]
            let z = vertexPointer[offset + 2]
            vertices.append(SIMD3<Float>(x, y, z))
        }
        
        // Extract normals if available
        if let normalAttribute = mesh.vertexDescriptor.attributeNamed(MDLVertexAttributeNormal) as? MDLVertexAttribute {
            let normalBuffer = mesh.vertexBuffers[normalAttribute.bufferIndex]
            let normalStride = normalBuffer.length / vertexCount
            let normalPointer = normalBuffer.map().bytes.bindMemory(to: Float.self, capacity: vertexCount * normalStride)
            
            for i in 0..<vertexCount {
                let offset = i * normalStride / MemoryLayout<Float>.stride
                let nx = normalPointer[offset]
                let ny = normalPointer[offset + 1]
                let nz = normalPointer[offset + 2]
                normals.append(SIMD3<Float>(nx, ny, nz))
            }
        }
        
        return MeshData(
            vertices: vertices,
            normals: normals,
            triangles: mesh.submeshes?.compactMap { $0 as? MDLSubmesh }.flatMap { 
                let buffer = $0.indexBuffer
                return buffer.map { buffer in
                    return buffer.bytes.bindMemory(to: UInt32.self, capacity: buffer.length / MemoryLayout<UInt32>.stride)
                }
            } ?? []
        )
    }
    
    public enum ConversionError: Error {
        case invalidMeshData
        case missingVertexData
        case fileWriteError
    }
}

public public struct MeshData {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let triangles: [UInt32]
    
    public func calculateNormals() -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: vertices.count)
        
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let i0 = Int(triangles[i])
            let i1 = Int(triangles[i + 1])
            let i2 = Int(triangles[i + 2])
            
            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]
            
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))
            
            normals[i0] += normal
            normals[i1] += normal
            normals[i2] += normal
        }
        
        return normals.map { normalize($0) }
    }
}
