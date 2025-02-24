import Foundation
import Metal
import simd

final class BatchProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let maxBatchSize: Int
    private var pipelineState: MTLComputePipelineState?
    private var currentBatchSize: Int
    private let defaultBatchSize: Int
    
    init(maxBatchSize: Int = 1000) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw ProcessingError.metalInitializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.maxBatchSize = maxBatchSize
        self.defaultBatchSize = maxBatchSize
        self.currentBatchSize = maxBatchSize
        
        try setupPipeline()
    }
    
    func adjustBatchSize(factor: Double) {
        currentBatchSize = max(100, Int(Double(currentBatchSize) * factor))
    }

    func resetBatchSize() {
        currentBatchSize = defaultBatchSize
    }

    func processBatch<T>(_ data: [T], operation: BatchOperation) throws -> [T] {
        var processedData: [T] = []
        let batches = stride(from: 0, to: data.count, by: currentBatchSize) // Use currentBatchSize instead of maxBatchSize
        
        for batchStart in batches {
            let batchEnd = min(batchStart + currentBatchSize, data.count)
            let batch = Array(data[batchStart..<batchEnd])
            
            autoreleasepool {
                if let processed = try? processOnGPU(batch, operation: operation) {
                    processedData.append(contentsOf: processed)
                } else {
                    // Fallback to CPU processing if GPU fails
                    let processed = processBatchOnCPU(batch, operation: operation)
                    processedData.append(contentsOf: processed)
                }
            }
        }
        
        return processedData
    }
    
    private func setupPipeline() throws {
        let library = try device.makeDefaultLibrary()
        guard let kernelFunction = library.makeFunction(name: "processPointsKernel") else {
            throw ProcessingError.kernelNotFound
        }
        
        pipelineState = try device.makeComputePipelineState(function: kernelFunction)
    }
    
    private func processOnGPU<T>(_ batch: [T], operation: BatchOperation) throws -> [T] {
        guard let pipelineState = pipelineState else {
            throw ProcessingError.pipelineNotInitialized
        }
        
        let inputBuffer = device.makeBuffer(bytes: batch,
                                          length: batch.count * MemoryLayout<T>.stride,
                                          options: .storageModeShared)
        
        let outputBuffer = device.makeBuffer(length: batch.count * MemoryLayout<T>.stride,
                                           options: .storageModeShared)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessingError.commandBufferCreationFailed
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        
        let gridSize = MTLSize(width: batch.count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: min(pipelineState.maxTotalThreadsPerThreadgroup, batch.count),
                                    height: 1,
                                    depth: 1)
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputBuffer.contents().assumingMemoryBound(to: T.self)
    }
    
    private func processBatchOnCPU<T>(_ batch: [T], operation: BatchOperation) -> [T] {
        return batch.map { operation.process($0) }
    }
}

enum BatchOperation {
    case denoise
    case normalize
    case downsample
    
    func process<T>(_ input: T) -> T {
        switch self {
        case .denoise:
            return denoisePoint(input)
        case .normalize:
            return normalizePoint(input)
        case .downsample:
            return input // Downsampling happens at batch level
        }
    }
    
    private func denoisePoint<T>(_ point: T) -> T {
        // Implement point-level denoising
        return point
    }
    
    private func normalizePoint<T>(_ point: T) -> T {
        // Implement point normalization
        return point
    }
}

enum ProcessingError: Error {
    case metalInitializationFailed
    case kernelNotFound
    case pipelineNotInitialized
    case commandBufferCreationFailed
}