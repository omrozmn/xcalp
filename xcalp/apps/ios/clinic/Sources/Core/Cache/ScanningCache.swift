import Foundation
import Metal
import os.log

public actor ScanningCache {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningCache")
    private let device: MTLDevice
    private var meshCache: [UUID: CachedMesh] = [:]
    private var frameCache: [UUID: CachedFrame] = [:]
    
    private let maxMeshCacheSize = 5 // Maximum number of meshes to keep in memory
    private let maxFrameCacheSize = 30 // Maximum number of frames to keep in memory
    
    struct CachedMesh {
        let vertices: MTLBuffer
        let normals: MTLBuffer
        let indices: MTLBuffer
        let timestamp: Date
        let quality: QualityAssessment
    }
    
    struct CachedFrame {
        let depthData: Data
        let confidenceData: Data
        let timestamp: Date
    }
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    public func cacheMesh(
        id: UUID,
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        indices: [UInt32],
        quality: QualityAssessment
    ) throws {
        // Create Metal buffers
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let normalBuffer = device.makeBuffer(
            bytes: normals,
            length: normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw CacheError.bufferCreationFailed
        }
        
        // Add to cache
        meshCache[id] = CachedMesh(
            vertices: vertexBuffer,
            normals: normalBuffer,
            indices: indexBuffer,
            timestamp: Date(),
            quality: quality
        )
        
        // Manage cache size
        if meshCache.count > maxMeshCacheSize {
            removeOldestMesh()
        }
        
        logger.debug("Cached mesh with ID: \(id.uuidString)")
    }
    
    public func cacheFrame(
        id: UUID,
        depthData: Data,
        confidenceData: Data
    ) {
        frameCache[id] = CachedFrame(
            depthData: depthData,
            confidenceData: confidenceData,
            timestamp: Date()
        )
        
        if frameCache.count > maxFrameCacheSize {
            removeOldestFrame()
        }
        
        logger.debug("Cached frame with ID: \(id.uuidString)")
    }
    
    public func getMesh(id: UUID) -> CachedMesh? {
        return meshCache[id]
    }
    
    public func getFrame(id: UUID) -> CachedFrame? {
        return frameCache[id]
    }
    
    public func clearCache() {
        meshCache.removeAll()
        frameCache.removeAll()
        logger.info("Cache cleared")
    }
    
    private func removeOldestMesh() {
        guard let oldest = meshCache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        meshCache.removeValue(forKey: oldest.key)
        logger.debug("Removed oldest mesh from cache: \(oldest.key.uuidString)")
    }
    
    private func removeOldestFrame() {
        guard let oldest = frameCache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        frameCache.removeValue(forKey: oldest.key)
        logger.debug("Removed oldest frame from cache: \(oldest.key.uuidString)")
    }
}

enum CacheError: Error {
    case bufferCreationFailed
    case meshNotFound
    case frameNotFound
}