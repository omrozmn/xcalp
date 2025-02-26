import Foundation
import Metal
import simd

final class BilateralMeshFilter {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    
    struct FilterParameters {
        var spatialSigma: Float
        var normalSigma: Float
        var iterations: Int
        var featurePreservationWeight: Float
        
        static let `default` = FilterParameters(
            spatialSigma: 0.01,  // 1cm
            normalSigma: 0.5,    // cos(60°)
            iterations: 3,
            featurePreservationWeight: 0.8
        )
    }
    
    init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "bilateralFilterKernel") else {
            throw FilterError.initializationFailed
        }
        
        self.commandQueue = queue
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
    
    func filter(_ mesh: MeshData, parameters: FilterParameters = .default) async throws -> MeshData {
        var filteredMesh = mesh
        let bufferManager = MeshBufferManager(device: device)
        
        for _ in 0..<parameters.iterations {
            // Upload mesh data to GPU
            let buffers = try bufferManager.upload(filteredMesh)
            
            // Allocate output buffers
            guard let outputVertices = device.makeBuffer(length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
                                                       options: .storageModeShared),
                  let outputNormals = device.makeBuffer(length: mesh.normals.count * MemoryLayout<SIMD3<Float>>.stride,
                                                      options: .storageModeShared) else {
                throw FilterError.bufferAllocationFailed
            }
            
            // Create command buffer and encoder
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw FilterError.commandEncodingFailed
            }
            
            encoder.setComputePipelineState(pipelineState)
            encoder.setBuffer(buffers.vertices, offset: 0, index: 0)
            encoder.setBuffer(buffers.normals, offset: 0, index: 1)
            encoder.setBuffer(buffers.confidence, offset: 0, index: 2)
            encoder.setBuffer(outputVertices, offset: 0, index: 3)
            encoder.setBuffer(outputNormals, offset: 0, index: 4)
            
            var params = parameters
            encoder.setBytes(&params, length: MemoryLayout<FilterParameters>.stride, index: 5)
            
            // Dispatch compute work
            let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
            let threadGroups = MTLSize(
                width: (mesh.vertices.count + 63) / 64,
                height: 1,
                depth: 1
            )
            
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
            
            // Execute and wait for completion
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // Update mesh with filtered results
            let vertices = Array(UnsafeBufferPointer(
                start: outputVertices.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                count: mesh.vertices.count
            ))
            
            let normals = Array(UnsafeBufferPointer(
                start: outputNormals.contents().assumingMemoryBound(to: SIMD3<Float>.self),
                count: mesh.normals.count
            ))
            
            filteredMesh = MeshData(
                vertices: vertices,
                indices: mesh.indices,
                normals: normals,
                confidence: mesh.confidence,
                metadata: mesh.metadata
            )
            
            // Update processing history
            filteredMesh.metadata.processingSteps.append(
                ProcessingStep(
                    operation: "bilateralFilter",
                    timestamp: Date(),
                    parameters: [
                        "spatialSigma": String(parameters.spatialSigma),
                        "normalSigma": String(parameters.normalSigma),
                        "iteration": String(parameters.iterations)
                    ],
                    qualityImpact: nil
                )
            )
        }
        
        return filteredMesh
    }
}

enum FilterError: Error {
    case initializationFailed
    case bufferAllocationFailed
    case commandEncodingFailed
}