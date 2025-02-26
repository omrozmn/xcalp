import Foundation
import Metal
import simd

final class MarchingCubes {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let lookupTable: MTLBuffer
    
    init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "marchingCubesKernel") else {
            throw MarchingCubesError.initializationFailed
        }
        
        self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        // Initialize marching cubes lookup table
        let table = Self.createTriangleTable()
        guard let buffer = device.makeBuffer(bytes: table,
                                           length: MemoryLayout<UInt8>.size * 256 * 16,
                                           options: .storageModeShared) else {
            throw MarchingCubesError.initializationFailed
        }
        self.lookupTable = buffer
    }
    
    func extract(from field: [Float], gridSize: SIMD3<Int>, isoLevel: Float = 0.0) throws -> MeshData {
        // Allocate buffers for vertices and indices
        let maxVertices = gridSize.x * gridSize.y * gridSize.z * 12 // Maximum possible vertices
        let maxIndices = maxVertices * 3 // Maximum possible indices
        
        guard let vertexBuffer = device.makeBuffer(length: maxVertices * MemoryLayout<SIMD3<Float>>.stride,
                                                 options: .storageModeShared),
              let normalBuffer = device.makeBuffer(length: maxVertices * MemoryLayout<SIMD3<Float>>.stride,
                                                 options: .storageModeShared),
              let indexBuffer = device.makeBuffer(length: maxIndices * MemoryLayout<UInt32>.stride,
                                                options: .storageModeShared),
              let counterBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride * 2,
                                                  options: .storageModeShared),
              let fieldBuffer = device.makeBuffer(bytes: field,
                                                length: field.count * MemoryLayout<Float>.stride,
                                                options: .storageModeShared) else {
            throw MarchingCubesError.bufferAllocationFailed
        }
        
        // Reset counters
        let counters = counterBuffer.contents().assumingMemoryBound(to: UInt32.self)
        counters[0] = 0 // vertex count
        counters[1] = 0 // index count
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MarchingCubesError.encodingFailed
        }
        
        // Set up compute encoder
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(fieldBuffer, offset: 0, index: 0)
        encoder.setBuffer(vertexBuffer, offset: 0, index: 1)
        encoder.setBuffer(normalBuffer, offset: 0, index: 2)
        encoder.setBuffer(indexBuffer, offset: 0, index: 3)
        encoder.setBuffer(counterBuffer, offset: 0, index: 4)
        encoder.setBuffer(lookupTable, offset: 0, index: 5)
        encoder.setBytes([isoLevel], length: MemoryLayout<Float>.stride, index: 6)
        encoder.setBytes([gridSize], length: MemoryLayout<SIMD3<Int>>.stride, index: 7)
        
        // Calculate grid dimensions
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, height: 8)
        let threadgroups = MTLSize(
            width: (gridSize.x + 7) / 8,
            height: (gridSize.y + 7) / 8,
            depth: (gridSize.z + 7) / 8
        )
        
        // Dispatch compute work
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let vertexCount = Int(counters[0])
        let indexCount = Int(counters[1])
        
        let vertices = Array(UnsafeBufferPointer(
            start: vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
            count: vertexCount
        ))
        
        let normals = Array(UnsafeBufferPointer(
            start: normalBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
            count: vertexCount
        ))
        
        let indices = Array(UnsafeBufferPointer(
            start: indexBuffer.contents().assumingMemoryBound(to: UInt32.self),
            count: indexCount
        ))
        
        // Create confidence values (high confidence for marching cubes results)
        let confidence = Array(repeating: Float(1.0), count: vertexCount)
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .reconstruction)
        )
    }
    
    private static func createTriangleTable() -> [UInt8] {
        // Standard marching cubes triangle table
        // This table defines how to triangulate each cube configuration
        // Format: For each of the 256 possible cube configurations:
        // - 15 values per configuration
        // - First 12 values are edge indices for vertices
        // - Last 3 values are unused (padding)
        // The actual table data would be quite long, so it's omitted here
        return [] // Implementation needed - standard MC table
    }
}

enum MarchingCubesError: Error {
    case initializationFailed
    case bufferAllocationFailed
    case encodingFailed
}