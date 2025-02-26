import Foundation
import Metal
import MetalKit

final class GPUMemoryManager {
    private let device: MTLDevice
    private let maxBufferSize: Int = 128 * 1024 * 1024 // 128MB chunk size
    private let queue = DispatchQueue(label: "com.xcalp.gpumemory", qos: .userInitiated)
    private var allocatedBuffers: [Int: MTLBuffer] = [:] // buffer ID -> buffer
    private var activeChunks: Set<Int> = []
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func allocateBuffer(
        forMesh mesh: MeshData,
        completion: @escaping (Result<[MTLBuffer], Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let buffers = try self.createChunkedBuffers(from: mesh)
                completion(.success(buffers))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func releaseBuffer(withId id: Int) {
        queue.async { [weak self] in
            self?.allocatedBuffers.removeValue(forKey: id)
            self?.activeChunks.remove(id)
        }
    }
    
    func purgeInactiveBuffers() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let inactiveBuffers = Set(self.allocatedBuffers.keys).subtracting(self.activeChunks)
            for id in inactiveBuffers {
                self.allocatedBuffers.removeValue(forKey: id)
            }
        }
    }
    
    private func createChunkedBuffers(from mesh: MeshData) throws -> [MTLBuffer] {
        let vertexSize = MemoryLayout<SIMD3<Float>>.stride
        let totalSize = mesh.vertices.count * vertexSize
        let chunksNeeded = (totalSize + maxBufferSize - 1) / maxBufferSize
        
        var buffers: [MTLBuffer] = []
        
        for chunkIndex in 0..<chunksNeeded {
            let startIndex = chunkIndex * (maxBufferSize / vertexSize)
            let remainingVertices = mesh.vertices.count - startIndex
            let verticesInChunk = min(maxBufferSize / vertexSize, remainingVertices)
            
            let chunkData = Array(mesh.vertices[startIndex..<(startIndex + verticesInChunk)])
            
            guard let buffer = device.makeBuffer(
                bytes: chunkData,
                length: chunkData.count * vertexSize,
                options: .storageModeShared
            ) else {
                throw GPUMemoryError.bufferAllocationFailed
            }
            
            buffers.append(buffer)
            allocatedBuffers[chunkIndex] = buffer
            activeChunks.insert(chunkIndex)
        }
        
        return buffers
    }
}

enum GPUMemoryError: Error {
    case bufferAllocationFailed
    case invalidBufferSize
    case memoryLimitExceeded
}