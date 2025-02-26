import Foundation
import Metal
import ARKit
import MetalKit

extension MeshData {
    /// Initialize from ARMeshGeometry
    init(from meshGeometry: ARMeshGeometry) {
        let vertices = Array(UnsafeBufferPointer(start: meshGeometry.vertices.buffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                                                count: meshGeometry.vertices.count))
        
        let normals = Array(UnsafeBufferPointer(start: meshGeometry.normals.buffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                                               count: meshGeometry.normals.count))
        
        let indices = Array(UnsafeBufferPointer(start: meshGeometry.faces.buffer.contents().assumingMemoryBound(to: UInt32.self),
                                               count: meshGeometry.faces.count))
        
        // ARKit meshes start with high confidence
        let confidence = Array(repeating: Float(1.0), count: vertices.count)
        
        self.init(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .lidar)
        )
        
        updateBoundingBox()
    }
    
    /// Convert to MTLVertexDescriptor for rendering
    var metalVertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        
        // Position attribute
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        
        // Normal attribute
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0
        
        // Confidence attribute
        descriptor.attributes[2].format = .float
        descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        descriptor.attributes[2].bufferIndex = 0
        
        // Layout
        descriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<Float>.stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex
        
        return descriptor
    }
    
    /// Create vertex and index buffers for Metal rendering
    func createMetalBuffers(device: MTLDevice) -> (vertices: MTLBuffer, indices: MTLBuffer)? {
        // Interleave vertex data (position, normal, confidence)
        var vertexData = [Float]()
        vertexData.reserveCapacity(vertices.count * 7) // 3 for position + 3 for normal + 1 for confidence
        
        for i in 0..<vertices.count {
            vertexData.append(contentsOf: [vertices[i].x, vertices[i].y, vertices[i].z])
            vertexData.append(contentsOf: [normals[i].x, normals[i].y, normals[i].z])
            vertexData.append(confidence[i])
        }
        
        guard let vertexBuffer = device.makeBuffer(bytes: vertexData,
                                                 length: vertexData.count * MemoryLayout<Float>.size,
                                                 options: .storageModeShared),
              let indexBuffer = device.makeBuffer(bytes: indices,
                                                length: indices.count * MemoryLayout<UInt32>.size,
                                                options: .storageModeShared) else {
            return nil
        }
        
        return (vertexBuffer, indexBuffer)
    }
    
    /// Convert to MDLMesh for Model I/O operations
    func createMDLMesh(device: MTLDevice) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        
        // Create vertex buffer
        let vertexBuffer = allocator.newBuffer(MemoryLayout<SIMD3<Float>>.stride * vertices.count,
                                             type: .vertex)
        let normalBuffer = allocator.newBuffer(MemoryLayout<SIMD3<Float>>.stride * normals.count,
                                             type: .vertex)
        let confidenceBuffer = allocator.newBuffer(MemoryLayout<Float>.stride * confidence.count,
                                                 type: .vertex)
        
        // Copy data
        memcpy(vertexBuffer.contents(), vertices, vertices.count * MemoryLayout<SIMD3<Float>>.size)
        memcpy(normalBuffer.contents(), normals, normals.count * MemoryLayout<SIMD3<Float>>.size)
        memcpy(confidenceBuffer.contents(), confidence, confidence.count * MemoryLayout<Float>.size)
        
        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                          format: .float3,
                                                          offset: 0,
                                                          bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                          format: .float3,
                                                          offset: 0,
                                                          bufferIndex: 1)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: "confidence",
                                                          format: .float,
                                                          offset: 0,
                                                          bufferIndex: 2)
        
        // Create submesh
        let indexBuffer = allocator.newBuffer(MemoryLayout<UInt32>.stride * indices.count,
                                            type: .index)
        memcpy(indexBuffer.contents(), indices, indices.count * MemoryLayout<UInt32>.size)
        
        let submesh = MDLSubmesh(indexBuffer: indexBuffer,
                                indexCount: indices.count,
                                indexType: .uint32,
                                geometryType: .triangles,
                                material: nil)
        
        // Create mesh
        return MDLMesh(vertexBuffers: [vertexBuffer, normalBuffer, confidenceBuffer],
                      vertexCount: vertices.count,
                      descriptor: vertexDescriptor,
                      submeshes: [submesh])
    }
}