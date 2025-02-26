import Metal
import MetalKit
import simd
import os.log

class MeshFeatureAnalyzer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let featureDetectionPipeline: MTLComputePipelineState
    private let featurePreservationPipeline: MTLComputePipelineState
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshFeatures")
    
    struct Feature {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let curvature: Float
        let importance: Float
    }
    
    struct FeaturePreservationOptions {
        let curvatureThreshold: Float
        let featureRadius: Float
        let preservationStrength: Float
        
        static let `default` = FeaturePreservationOptions(
            curvatureThreshold: 0.7,
            featureRadius: 0.05,
            preservationStrength: 0.8
        )
    }
    
    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let detectFunction = library.makeFunction(name: "detectFeaturesKernel"),
              let preserveFunction = library.makeFunction(name: "preserveFeaturesKernel") else {
            throw FeatureAnalysisError.initializationFailed
        }
        
        self.commandQueue = commandQueue
        self.featureDetectionPipeline = try device.makeComputePipelineState(function: detectFunction)
        self.featurePreservationPipeline = try device.makeComputePipelineState(function: preserveFunction)
    }
    
    func detectFeatures(_ mesh: MTKMesh, options: FeaturePreservationOptions = .default) throws -> [Feature] {
        return try autoreleasepool {
            // Prepare vertex data
            let vertexBuffer = try getVertexBuffer(mesh)
            let featureBuffer = try createFeatureBuffer(vertexCount: mesh.vertexCount)
            
            // Run feature detection
            try detectFeatures(
                vertexBuffer: vertexBuffer,
                featureBuffer: featureBuffer,
                options: options
            )
            
            // Process results
            return try extractFeatures(from: featureBuffer, vertexCount: mesh.vertexCount)
        }
    }
    
    func preserveFeatures(_ mesh: MTKMesh, features: [Feature]) throws -> MTKMesh {
        return try autoreleasepool {
            // Create feature buffer
            let featureData = features.flatMap {
                [
                    $0.position.x, $0.position.y, $0.position.z,
                    $0.normal.x, $0.normal.y, $0.normal.z,
                    $0.curvature,
                    $0.importance
                ]
            }
            
            guard let featureBuffer = device.makeBuffer(
                bytes: featureData,
                length: featureData.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ) else {
                throw FeatureAnalysisError.bufferCreationFailed
            }
            
            // Apply feature preservation
            return try preserveMeshFeatures(
                mesh: mesh,
                featureBuffer: featureBuffer,
                featureCount: features.count
            )
        }
    }
    
    private func detectFeatures(
        vertexBuffer: MTLBuffer,
        featureBuffer: MTLBuffer,
        options: FeaturePreservationOptions
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FeatureAnalysisError.commandEncodingFailed
        }
        
        // Configure compute pipeline
        computeEncoder.setComputePipelineState(featureDetectionPipeline)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(featureBuffer, offset: 0, index: 1)
        
        // Set detection parameters
        var params = FeatureDetectionParams(
            curvatureThreshold: options.curvatureThreshold,
            featureRadius: options.featureRadius
        )
        computeEncoder.setBytes(
            &params,
            length: MemoryLayout<FeatureDetectionParams>.stride,
            index: 2
        )
        
        // Calculate dispatch size
        let vertexCount = vertexBuffer.length / MemoryLayout<Vertex>.stride
        let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
        let threadgroupCount = MTLSize(
            width: (vertexCount + 63) / 64,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func preserveMeshFeatures(
        mesh: MTKMesh,
        featureBuffer: MTLBuffer,
        featureCount: Int
    ) throws -> MTKMesh {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FeatureAnalysisError.commandEncodingFailed
        }
        
        let vertexBuffer = try getVertexBuffer(mesh)
        
        // Configure preservation pipeline
        computeEncoder.setComputePipelineState(featurePreservationPipeline)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(featureBuffer, offset: 0, index: 1)
        
        var params = PreservationParams(
            featureCount: UInt32(featureCount),
            preservationStrength: FeaturePreservationOptions.default.preservationStrength
        )
        computeEncoder.setBytes(
            &params,
            length: MemoryLayout<PreservationParams>.stride,
            index: 2
        )
        
        // Calculate dispatch size
        let vertexCount = vertexBuffer.length / MemoryLayout<Vertex>.stride
        let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
        let threadgroupCount = MTLSize(
            width: (vertexCount + 63) / 64,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return try createUpdatedMesh(mesh, vertexBuffer: vertexBuffer)
    }
    
    private func getVertexBuffer(_ mesh: MTKMesh) throws -> MTLBuffer {
        guard let vertexBuffer = mesh.vertexBuffers[0].buffer else {
            throw FeatureAnalysisError.invalidMeshData
        }
        return vertexBuffer
    }
    
    private func createFeatureBuffer(vertexCount: Int) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(
            length: vertexCount * MemoryLayout<Feature>.stride,
            options: .storageModeShared
        ) else {
            throw FeatureAnalysisError.bufferCreationFailed
        }
        return buffer
    }
    
    private func extractFeatures(from buffer: MTLBuffer, vertexCount: Int) -> [Feature] {
        let featureData = buffer.contents().bindMemory(
            to: Float.self,
            capacity: vertexCount * 8 // position(3) + normal(3) + curvature + importance
        )
        
        var features: [Feature] = []
        for i in stride(from: 0, to: vertexCount * 8, by: 8) {
            let position = SIMD3<Float>(
                featureData[i],
                featureData[i + 1],
                featureData[i + 2]
            )
            let normal = SIMD3<Float>(
                featureData[i + 3],
                featureData[i + 4],
                featureData[i + 5]
            )
            let curvature = featureData[i + 6]
            let importance = featureData[i + 7]
            
            if importance > 0.5 { // Only include significant features
                features.append(Feature(
                    position: position,
                    normal: normal,
                    curvature: curvature,
                    importance: importance
                ))
            }
        }
        
        return features
    }
    
    private func createUpdatedMesh(_ originalMesh: MTKMesh, vertexBuffer: MTLBuffer) throws -> MTKMesh {
        // Create new mesh with updated vertices
        let meshDescriptor = MTKMeshDescriptor(originalMesh)
        meshDescriptor.vertexBuffers[0].data = vertexBuffer.contents()
        
        return try MTKMesh(
            mesh: meshDescriptor,
            device: device
        )
    }
}

// MARK: - Supporting Types

private struct FeatureDetectionParams {
    let curvatureThreshold: Float
    let featureRadius: Float
}

private struct PreservationParams {
    let featureCount: UInt32
    let preservationStrength: Float
}

private struct Vertex {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
}

enum FeatureAnalysisError: Error {
    case initializationFailed
    case bufferCreationFailed
    case commandEncodingFailed
    case invalidMeshData
}