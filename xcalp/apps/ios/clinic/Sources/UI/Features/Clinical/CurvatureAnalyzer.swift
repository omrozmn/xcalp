import Foundation
import Metal
import simd

final class CurvatureAnalyzer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let curvaturePipeline: MTLComputePipelineState
    private let memoryManager: GPUMemoryManager
    private let chunkProcessor: ChunkProcessor
    
    private let resolution = 100
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let curvatureFunction = library.makeFunction(name: "computeCurvature") else {
            throw CurvatureError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.curvaturePipeline = try device.makeComputePipelineState(function: curvatureFunction)
        self.memoryManager = GPUMemoryManager(device: device)
        self.chunkProcessor = ChunkProcessor()
    }
    
    func analyzeCurvature(_ mesh: MeshData) async throws -> [[Float]] {
        // Process mesh in chunks to handle large datasets efficiently
        let chunks = try await processInChunks(mesh)
        return combineChunkResults(chunks)
    }
    
    func analyzeFeatures(_ mesh: MeshData) async throws -> CurvatureFeatures {
        let curvatureMap = try await analyzeCurvature(mesh)
        
        // Compute various curvature-based features
        let meanCurvature = calculateMeanCurvature(curvatureMap)
        let gaussianCurvature = try await calculateGaussianCurvature(mesh)
        let principalCurvatures = calculatePrincipalCurvatures(
            meanCurvature: meanCurvature,
            gaussianCurvature: gaussianCurvature
        )
        
        return CurvatureFeatures(
            meanCurvature: meanCurvature,
            gaussianCurvature: gaussianCurvature,
            principalCurvatures: principalCurvatures,
            shapeIndex: calculateShapeIndex(principalCurvatures),
            curvednessIndex: calculateCurvednessIndex(principalCurvatures)
        )
    }
    
    private func processInChunks(_ mesh: MeshData) async throws -> [[[Float]]] {
        // Allocate buffers for mesh data
        let buffers = try await memoryManager.allocateBuffer(forMesh: mesh)
        
        // Process each chunk
        var results: [[[Float]]] = []
        for buffer in buffers {
            let result = try await chunkProcessor.processSingleBuffer(
                buffer,
                device: device,
                commandQueue: commandQueue,
                resolution: resolution
            )
            results.append(result)
        }
        
        return results
    }
    
    private func combineChunkResults(_ chunks: [[[Float]]]) -> [[Float]] {
        chunkProcessor.combineChunkResults(chunks, resolution: resolution)
    }
    
    private func calculateMeanCurvature(_ curvatureMap: [[Float]]) -> [[Float]] {
        // Mean curvature is already computed by our shader
        return curvatureMap
    }
    
    private func calculateGaussianCurvature(_ mesh: MeshData) async throws -> [[Float]] {
        var gaussianCurvature = Array(
            repeating: Array(repeating: Float(0), count: resolution),
            count: resolution
        )
        
        // Create buffers for computation
        guard let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let normalBuffer = device.makeBuffer(
            bytes: mesh.normals,
            length: mesh.normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        ),
        let outputBuffer = device.makeBuffer(
            length: resolution * resolution * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw CurvatureError.bufferCreationFailed
        }
        
        // Set up compute command
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw CurvatureError.encodingFailed
        }
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (resolution + 7) / 8,
            height: (resolution + 7) / 8,
            depth: 1
        )
        
        // Configure and dispatch compute shader
        computeEncoder.setComputePipelineState(curvaturePipeline)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let outputPtr = outputBuffer.contents().assumingMemoryBound(to: Float.self)
        for y in 0..<resolution {
            for x in 0..<resolution {
                gaussianCurvature[y][x] = outputPtr[y * resolution + x]
            }
        }
        
        return gaussianCurvature
    }
    
    private func calculatePrincipalCurvatures(
        meanCurvature: [[Float]],
        gaussianCurvature: [[Float]]
    ) -> [[(k1: Float, k2: Float)]] {
        var principalCurvatures = Array(
            repeating: Array(repeating: (k1: Float(0), k2: Float(0)),
                           count: resolution),
            count: resolution
        )
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let H = meanCurvature[y][x]
                let K = gaussianCurvature[y][x]
                
                // Principal curvatures from mean (H) and Gaussian (K) curvatures
                // H = (k1 + k2)/2
                // K = k1 * k2
                let discriminant = H * H - K
                if discriminant >= 0 {
                    let sqrtD = sqrt(discriminant)
                    principalCurvatures[y][x] = (
                        k1: H + sqrtD,
                        k2: H - sqrtD
                    )
                }
            }
        }
        
        return principalCurvatures
    }
    
    private func calculateShapeIndex(_ principalCurvatures: [[(k1: Float, k2: Float)]]) -> [[Float]] {
        var shapeIndex = Array(
            repeating: Array(repeating: Float(0), count: resolution),
            count: resolution
        )
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let (k1, k2) = principalCurvatures[y][x]
                if k1 != k2 {
                    // Shape index formula: S = (2/π) * arctan((k1 + k2)/(k1 - k2))
                    shapeIndex[y][x] = (2.0 / .pi) * atan((k1 + k2) / (k1 - k2))
                }
            }
        }
        
        return shapeIndex
    }
    
    private func calculateCurvednessIndex(_ principalCurvatures: [[(k1: Float, k2: Float)]]) -> [[Float]] {
        var curvednessIndex = Array(
            repeating: Array(repeating: Float(0), count: resolution),
            count: resolution
        )
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                let (k1, k2) = principalCurvatures[y][x]
                // Curvedness index formula: C = sqrt((k1² + k2²)/2)
                curvednessIndex[y][x] = sqrt((k1 * k1 + k2 * k2) / 2.0)
            }
        }
        
        return curvednessIndex
    }
}

struct CurvatureFeatures {
    let meanCurvature: [[Float]]
    let gaussianCurvature: [[Float]]
    let principalCurvatures: [[(k1: Float, k2: Float)]]
    let shapeIndex: [[Float]]
    let curvednessIndex: [[Float]]
}

enum CurvatureError: Error {
    case initializationFailed
    case bufferCreationFailed
    case encodingFailed
    case computationFailed
}