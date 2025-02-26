import Foundation
import Metal
import simd

final class ChunkProcessor {
    private let maxThreadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
    
    func processSingleBuffer(
        _ buffer: MTLBuffer,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        resolution: Int
    ) async throws -> [[Float?]] {
        var result = Array(repeating: Array(repeating: nil as Float?, count: resolution), count: resolution)
        
        // Create output buffer for curvature data
        guard let curvatureBuffer = device.makeBuffer(
            length: resolution * resolution * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw ProcessingError.bufferCreationFailed
        }
        
        // Set up compute pipeline
        guard let library = try? device.makeDefaultLibrary(),
              let computeFunction = library.makeFunction(name: "computeCurvature"),
              let computePipelineState = try? device.makeComputePipelineState(function: computeFunction) else {
            throw ProcessingError.pipelineCreationFailed
        }
        
        // Calculate thread groups
        let threadGroups = MTLSize(
            width: (resolution + maxThreadsPerGroup.width - 1) / maxThreadsPerGroup.width,
            height: (resolution + maxThreadsPerGroup.height - 1) / maxThreadsPerGroup.height,
            depth: 1
        )
        
        // Execute compute shader
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.commandEncodingFailed
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(buffer, offset: 0, index: 0)
        computeEncoder.setBuffer(curvatureBuffer, offset: 0, index: 1)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: maxThreadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Extract results
        let dataPointer = curvatureBuffer.contents().bindMemory(to: Float.self, capacity: resolution * resolution)
        for y in 0..<resolution {
            for x in 0..<resolution {
                let value = dataPointer[y * resolution + x]
                if value != 0 {
                    result[y][x] = value
                }
            }
        }
        
        return result
    }
    
    func combineChunkResults(_ results: [[[Float?]]], resolution: Int) -> [[Float]] {
        var combinedResult = Array(repeating: Array(repeating: Float.zero, count: resolution), count: resolution)
        var contributionCount = Array(repeating: Array(repeating: 0, count: resolution), count: resolution)
        
        // Combine all chunk results
        for chunkResult in results {
            for y in 0..<resolution {
                for x in 0..<resolution {
                    if let value = chunkResult[y][x] {
                        combinedResult[y][x] += value
                        contributionCount[y][x] += 1
                    }
                }
            }
        }
        
        // Average the results
        for y in 0..<resolution {
            for x in 0..<resolution {
                if contributionCount[y][x] > 0 {
                    combinedResult[y][x] /= Float(contributionCount[y][x])
                }
            }
        }
        
        return combinedResult
    }
}

enum ProcessingError: Error {
    case bufferCreationFailed
    case pipelineCreationFailed
    case commandEncodingFailed
    case invalidChunkData
}