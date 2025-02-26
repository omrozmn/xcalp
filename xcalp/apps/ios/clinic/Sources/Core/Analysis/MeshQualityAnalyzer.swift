import Metal
import MetalKit
import ARKit

public class MeshQualityAnalyzer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let analysisShader: MTLComputePipelineState
    
    public init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw MeshQualityError.deviceInitializationFailed
        }
        self.commandQueue = queue
        
        // Initialize Metal compute pipeline for mesh analysis
        guard let library = device.makeDefaultLibrary(),
              let analysisFunction = library.makeFunction(name: "analyzeMeshQuality"),
              let pipeline = try? device.makeComputePipelineState(function: analysisFunction) else {
            throw MeshQualityError.shaderCompilationFailed
        }
        self.analysisShader = pipeline
    }
    
    public func analyzeMesh(_ mesh: ARMeshGeometry) async throws -> MeshQualityMetrics {
        let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices.buffer.contents(),
            length: mesh.vertices.stride * mesh.vertices.count,
            options: .storageModeShared
        )
        
        let normalBuffer = device.makeBuffer(
            bytes: mesh.normals.buffer.contents(),
            length: mesh.normals.stride * mesh.normals.count,
            options: .storageModeShared
        )
        
        guard let vertexBuffer = vertexBuffer,
              let normalBuffer = normalBuffer else {
            throw MeshQualityError.bufferAllocationFailed
        }
        
        let metrics = try await computeQualityMetrics(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            vertexCount: mesh.vertices.count
        )
        
        return metrics
    }
    
    private func computeQualityMetrics(
        vertexBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        vertexCount: Int
    ) async throws -> MeshQualityMetrics {
        let resultBuffer = device.makeBuffer(
            length: MemoryLayout<MeshQualityMetrics>.size,
            options: .storageModeShared
        )
        
        guard let resultBuffer = resultBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MeshQualityError.computeEncodingFailed
        }
        
        computeEncoder.setComputePipelineState(analysisShader)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(resultBuffer, offset: 0, index: 2)
        
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (vertexCount + threadGroupSize.width - 1) / threadGroupSize.width,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let metrics = resultBuffer.contents().load(as: MeshQualityMetrics.self)
        return metrics
    }
}

public struct MeshQualityMetrics {
    public let vertexDensity: Float
    public let averageTriangleArea: Float
    public let normalConsistency: Float
    public let boundaryLength: Float
    public let surfaceCurvature: Float
    
    public var qualityScore: Float {
        // Weighted combination of metrics
        let densityWeight: Float = 0.3
        let areaWeight: Float = 0.2
        let normalWeight: Float = 0.2
        let boundaryWeight: Float = 0.15
        let curvatureWeight: Float = 0.15
        
        return vertexDensity * densityWeight +
               (1.0 - averageTriangleArea) * areaWeight +
               normalConsistency * normalWeight +
               (1.0 - boundaryLength) * boundaryWeight +
               (1.0 - surfaceCurvature) * curvatureWeight
    }
}

public enum MeshQualityError: Error {
    case deviceInitializationFailed
    case shaderCompilationFailed
    case bufferAllocationFailed
    case computeEncodingFailed
}