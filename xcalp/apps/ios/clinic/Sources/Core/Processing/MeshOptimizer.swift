import Accelerate
import ARKit
import MetalKit
import Metal
import simd
import os.log

public class MeshOptimizer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let optimizationPipeline: MTLComputePipelineState
    private let decimationPipeline: MTLComputePipelineState
    private let smoothingPipeline: MTLComputePipelineState
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw OptimizationError.initializationFailed
        }
        self.commandQueue = queue
        
        // Initialize compute pipelines
        let library = try device.makeDefaultLibrary()
        
        self.optimizationPipeline = try Self.createPipeline(
            device: device,
            library: library,
            function: "optimizeMesh"
        )
        
        self.decimationPipeline = try Self.createPipeline(
            device: device,
            library: library,
            function: "decimateMesh"
        )
        
        self.smoothingPipeline = try Self.createPipeline(
            device: device,
            library: library,
            function: "smoothMesh"
        )
    }
    
    public func optimizeMesh(
        _ mesh: RawMesh,
        quality: QualityLevel
    ) async throws -> OptimizedMesh {
        // Create optimization parameters based on quality level
        let params = OptimizationParameters(quality: quality)
        
        // Initialize buffers
        let vertexBuffer = createBuffer(from: mesh.vertices)
        let normalBuffer = createBuffer(from: mesh.normals)
        let indexBuffer = createBuffer(from: mesh.indices)
        
        guard let vertexBuffer = vertexBuffer,
              let normalBuffer = normalBuffer,
              let indexBuffer = indexBuffer else {
            throw OptimizationError.bufferCreationFailed
        }
        
        // Step 1: Mesh decimation
        try await decimateMesh(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer,
            targetReduction: params.decimationRatio
        )
        
        // Step 2: Mesh smoothing
        try await smoothMesh(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            smoothingFactor: params.smoothingFactor
        )
        
        // Step 3: Final optimization
        try await performFinalOptimization(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer,
            params: params
        )
        
        // Convert back to CPU data
        let optimizedMesh = try extractOptimizedMesh(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer
        )
        
        return optimizedMesh
    }
    
    private func decimateMesh(
        vertexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        targetReduction: Float
    ) async throws {
        let commandBuffer = commandQueue.makeCommandBuffer()
        let computeEncoder = commandBuffer?.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(decimationPipeline)
        computeEncoder?.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder?.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder?.setBuffer(indexBuffer, offset: 0, index: 2)
        
        let reductionBuffer = device.makeBuffer(
            bytes: [targetReduction],
            length: MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        computeEncoder?.setBuffer(reductionBuffer, offset: 0, index: 3)
        
        let gridSize = MTLSize(
            width: vertexBuffer.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        
        computeEncoder?.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
    }
    
    private func smoothMesh(
        vertexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        smoothingFactor: Float
    ) async throws {
        let commandBuffer = commandQueue.makeCommandBuffer()
        let computeEncoder = commandBuffer?.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(smoothingPipeline)
        computeEncoder?.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder?.setBuffer(normalBuffer, offset: 0, index: 1)
        
        let factorBuffer = device.makeBuffer(
            bytes: [smoothingFactor],
            length: MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        computeEncoder?.setBuffer(factorBuffer, offset: 0, index: 2)
        
        let gridSize = MTLSize(
            width: vertexBuffer.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        
        computeEncoder?.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
    }
    
    private func performFinalOptimization(
        vertexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        params: OptimizationParameters
    ) async throws {
        let commandBuffer = commandQueue.makeCommandBuffer()
        let computeEncoder = commandBuffer?.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(optimizationPipeline)
        computeEncoder?.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder?.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder?.setBuffer(indexBuffer, offset: 0, index: 2)
        
        let paramsBuffer = device.makeBuffer(
            bytes: [params],
            length: MemoryLayout<OptimizationParameters>.size,
            options: .storageModeShared
        )
        computeEncoder?.setBuffer(paramsBuffer, offset: 0, index: 3)
        
        let gridSize = MTLSize(
            width: vertexBuffer.length / MemoryLayout<SIMD3<Float>>.stride,
            height: 1,
            depth: 1
        )
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        
        computeEncoder?.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
    }
    
    private func extractOptimizedMesh(
        vertexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer
    ) throws -> OptimizedMesh {
        let vertexCount = vertexBuffer.length / MemoryLayout<SIMD3<Float>>.stride
        let indexCount = indexBuffer.length / MemoryLayout<UInt32>.stride
        
        var vertices = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        
        memcpy(&vertices, vertexBuffer.contents(), vertexBuffer.length)
        memcpy(&normals, normalBuffer.contents(), normalBuffer.length)
        memcpy(&indices, indexBuffer.contents(), indexBuffer.length)
        
        return OptimizedMesh(
            vertices: vertices,
            normals: normals,
            indices: indices
        )
    }
    
    private func createBuffer<T>(from array: [T]) -> MTLBuffer? {
        device.makeBuffer(
            bytes: array,
            length: array.count * MemoryLayout<T>.stride,
            options: .storageModeShared
        )
    }
    
    private static func createPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        function: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: function) else {
            throw OptimizationError.pipelineCreationFailed
        }
        return try device.makeComputePipelineState(function: function)
    }
}

// MARK: - Supporting Types

public struct RawMesh {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
}

public struct OptimizedMesh {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
}

public struct OptimizationParameters {
    let decimationRatio: Float
    let smoothingFactor: Float
    let featurePreservation: Float
    let qualityThreshold: Float
    
    init(quality: QualityLevel) {
        switch quality {
        case .ultra:
            decimationRatio = 0.1
            smoothingFactor = 0.1
            featurePreservation = 0.95
            qualityThreshold = 0.95
        case .high:
            decimationRatio = 0.3
            smoothingFactor = 0.2
            featurePreservation = 0.9
            qualityThreshold = 0.9
        case .medium:
            decimationRatio = 0.5
            smoothingFactor = 0.3
            featurePreservation = 0.8
            qualityThreshold = 0.8
        case .low:
            decimationRatio = 0.7
            smoothingFactor = 0.4
            featurePreservation = 0.7
            qualityThreshold = 0.7
        }
    }
}

public enum OptimizationError: Error {
    case initializationFailed
    case pipelineCreationFailed
    case bufferCreationFailed
    case optimizationFailed
}