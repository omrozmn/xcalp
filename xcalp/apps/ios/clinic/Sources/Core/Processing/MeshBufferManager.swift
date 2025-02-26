import Foundation
import Metal
import simd

/// Manages efficient transfer of mesh data between CPU and GPU memory
final class MeshBufferManager {
    private let device: MTLDevice
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var normalBuffer: MTLBuffer?
    private var confidenceBuffer: MTLBuffer?
    
    private var currentVertexCount: Int = 0
    private var currentIndexCount: Int = 0
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func upload(_ mesh: MeshData) throws -> MeshBuffers {
        // Reallocate buffers if needed
        if mesh.vertices.count > currentVertexCount {
            vertexBuffer = device.makeBuffer(
                length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
                options: .storageModeShared
            )
            normalBuffer = device.makeBuffer(
                length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
                options: .storageModeShared
            )
            confidenceBuffer = device.makeBuffer(
                length: mesh.vertices.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
            currentVertexCount = mesh.vertices.count
        }
        
        if mesh.indices.count > currentIndexCount {
            indexBuffer = device.makeBuffer(
                length: mesh.indices.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
            currentIndexCount = mesh.indices.count
        }
        
        // Copy data to buffers
        guard let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer,
              let normalBuffer = normalBuffer,
              let confidenceBuffer = confidenceBuffer else {
            throw MeshError.bufferAllocationFailed
        }
        
        vertexBuffer.contents().copyMemory(
            from: mesh.vertices,
            byteCount: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride
        )
        
        indexBuffer.contents().copyMemory(
            from: mesh.indices,
            byteCount: mesh.indices.count * MemoryLayout<UInt32>.stride
        )
        
        normalBuffer.contents().copyMemory(
            from: mesh.normals,
            byteCount: mesh.normals.count * MemoryLayout<SIMD3<Float>>.stride
        )
        
        confidenceBuffer.contents().copyMemory(
            from: mesh.confidence,
            byteCount: mesh.confidence.count * MemoryLayout<Float>.stride
        )
        
        return MeshBuffers(
            vertices: vertexBuffer,
            indices: indexBuffer,
            normals: normalBuffer,
            confidence: confidenceBuffer,
            vertexCount: mesh.vertices.count,
            indexCount: mesh.indices.count
        )
    }
    
    func download(from buffers: MeshBuffers) -> MeshData {
        let vertices = Array<SIMD3<Float>>(
            UnsafeBufferPointer(
                start: buffers.vertices.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                count: buffers.vertexCount
            )
        )
        
        let indices = Array<UInt32>(
            UnsafeBufferPointer(
                start: buffers.indices.contents().assumingMemoryBound(to: UInt32.self),
                count: buffers.indexCount
            )
        )
        
        let normals = Array<SIMD3<Float>>(
            UnsafeBufferPointer(
                start: buffers.normals.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                count: buffers.vertexCount
            )
        )
        
        let confidence = Array<Float>(
            UnsafeBufferPointer(
                start: buffers.confidence.contents().assumingMemoryBound(to: Float.self),
                count: buffers.vertexCount
            )
        )
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence
        )
    }
}

struct MeshBuffers {
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let normals: MTLBuffer
    let confidence: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
}

enum MeshError: Error {
    case bufferAllocationFailed
}