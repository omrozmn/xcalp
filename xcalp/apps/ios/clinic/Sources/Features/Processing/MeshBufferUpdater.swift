import Foundation
import ModelIO
import Metal

class MeshBufferUpdater {
    private let device: MTLDevice?
    
    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }
    
    func updateVertexPositions(_ mesh: MDLMesh, with newPositions: [SIMD3<Float>]) throws -> MDLMesh {
        guard newPositions.count == mesh.vertexCount,
              let device = self.device else {
            throw MeshProcessingError.meshGenerationFailed
        }
        
        // Create new vertex buffer
        let vertexBuffer = device.makeBuffer(bytes: newPositions,
                                           length: newPositions.count * MemoryLayout<SIMD3<Float>>.stride,
                                           options: [])
        
        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                          format: .float3,
                                                          offset: 0,
                                                          bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        
        // Create new mesh with updated vertices but same topology
        let newMesh = MDLMesh(vertexBuffer: vertexBuffer!,
                             vertexCount: newPositions.count,
                             descriptor: vertexDescriptor,
                             submeshes: mesh.submeshes)
        
        // Copy other attributes if they exist
        if let normalBuffer = mesh.vertexBuffers[safe: 1]?.buffer {
            newMesh.vertexBuffers[1] = mesh.vertexBuffers[1]
        }
        
        return newMesh
    }
    
    func updateVertexNormals(_ mesh: MDLMesh) throws -> MDLMesh {
        guard let vertexBuffer = mesh.vertexBuffers.first?.buffer,
              let vertexData = vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
              let device = self.device else {
            throw MeshProcessingError.meshGenerationFailed
        }
        
        let vertices = Array(UnsafeBufferPointer(start: vertexData, count: mesh.vertexCount))
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.vertexCount)
        
        // Calculate normals for each face and accumulate to vertices
        for submesh in mesh.submeshes {
            guard let indexBuffer = submesh.indexBuffer,
                  let indexData = indexBuffer.contents().assumingMemoryBound(to: UInt32.self) else {
                continue
            }
            
            let indices = Array(UnsafeBufferPointer(start: indexData, count: submesh.indexCount))
            
            for i in stride(from: 0, to: indices.count, by: 3) {
                let v0 = vertices[Int(indices[i])]
                let v1 = vertices[Int(indices[i + 1])]
                let v2 = vertices[Int(indices[i + 2])]
                
                let normal = normalize(cross(v1 - v0, v2 - v0))
                
                normals[Int(indices[i])] += normal
                normals[Int(indices[i + 1])] += normal
                normals[Int(indices[i + 2])] += normal
            }
        }
        
        // Normalize accumulated normals
        normals = normals.map { normalize($0) }
        
        // Create normal buffer
        let normalBuffer = device.makeBuffer(bytes: normals,
                                           length: normals.count * MemoryLayout<SIMD3<Float>>.stride,
                                           options: [])
        
        // Update mesh with new normals
        let updatedMesh = mesh
        updatedMesh.vertexBuffers[1] = normalBuffer
        
        return updatedMesh
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}