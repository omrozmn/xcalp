import Metal
import MetalKit
import CoreML
import simd

final class PointCloudProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let qualityMetricsPipelineState: MTLComputePipelineState
    private let bilateralFilterPipelineState: MTLComputePipelineState
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "PointCloudProcessor")

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw ProcessingError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        // Initialize compute pipelines
        let qualityMetricsFunction = library.makeFunction(name: "calculateQualityMetricsKernel")
        let bilateralFilterFunction = library.makeFunction(name: "adaptiveBilateralFilterKernel")
        
        self.qualityMetricsPipelineState = try device.makeComputePipelineState(function: qualityMetricsFunction!)
        self.bilateralFilterPipelineState = try device.makeComputePipelineState(function: bilateralFilterFunction!)
    }
    
    func processPointCloud(_ points: [Point], parameters: ProcessingParameters) async throws -> ProcessedPointCloud {
        let pointCount = points.count
        
        // Create Metal buffers
        let pointsBuffer = device.makeBuffer(bytes: points,
                                           length: pointCount * MemoryLayout<Point>.stride,
                                           options: .storageModeShared)!
        
        let qualityBuffer = device.makeBuffer(length: pointCount * MemoryLayout<Float>.stride,
                                            options: .storageModeShared)!
        
        let parametersBuffer = device.makeBuffer(bytes: parameters.metalParameters,
                                               length: parameters.metalParameters.count * MemoryLayout<Float>.stride,
                                               options: .storageModeShared)!
        
        // Calculate quality metrics
        try computeQualityMetrics(
            points: pointsBuffer,
            quality: qualityBuffer,
            parameters: parametersBuffer,
            count: pointCount
        )
        
        // Apply adaptive bilateral filtering
        let filteredPoints = try applyBilateralFilter(
            points: pointsBuffer,
            parameters: parametersBuffer,
            count: pointCount
        )
        
        // Read back results
        let qualityScores = readQualityScores(from: qualityBuffer, count: pointCount)
        let processedPoints = readProcessedPoints(from: filteredPoints, count: pointCount)
        
        return ProcessedPointCloud(
            points: processedPoints,
            qualityScores: qualityScores,
            statistics: calculateStatistics(points: processedPoints, qualityScores: qualityScores)
        )
    }
    
    private func computeQualityMetrics(points: MTLBuffer, quality: MTLBuffer, parameters: MTLBuffer, count: Int) throws {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(qualityMetricsPipelineState)
        computeEncoder.setBuffer(points, offset: 0, index: 0)
        computeEncoder.setBuffer(quality, offset: 0, index: 1)
        computeEncoder.setBuffer(parameters, offset: 0, index: 2)
        
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func applyBilateralFilter(points: MTLBuffer, parameters: MTLBuffer, count: Int) throws -> MTLBuffer {
        let outputBuffer = device.makeBuffer(length: count * MemoryLayout<Point>.stride,
                                           options: .storageModeShared)!
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(bilateralFilterPipelineState)
        computeEncoder.setBuffer(points, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(parameters, offset: 0, index: 2)
        
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: 32, height: 1, depth: 1)
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputBuffer
    }
    
    private func readQualityScores(from buffer: MTLBuffer, count: Int) -> [Float] {
        let data = Data(bytes: buffer.contents(), count: count * MemoryLayout<Float>.stride)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    
    private func readProcessedPoints(from buffer: MTLBuffer, count: Int) -> [Point] {
        let data = Data(bytes: buffer.contents(), count: count * MemoryLayout<Point>.stride)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Point.self)) }
    }
    
    private func calculateStatistics(points: [Point], qualityScores: [Float]) -> ProcessingStatistics {
        var stats = ProcessingStatistics()
        
        stats.averageQuality = qualityScores.reduce(0, +) / Float(qualityScores.count)
        stats.pointCount = points.count
        stats.confidence = points.map { $0.confidence }.reduce(0, +) / Float(points.count)
        
        // Calculate density in points/cm²
        let boundingBox = calculateBoundingBox(points)
        let area = boundingBox.calculateSurfaceArea()
        stats.density = Float(points.count) / (area * 100) // Convert m² to cm²
        
        return stats
    }
}

struct ProcessingParameters {
    let searchRadius: Float
    let spatialSigma: Float
    let rangeSigma: Float
    let confidenceThreshold: Float
    
    var metalParameters: [Float] {
        [searchRadius, spatialSigma, rangeSigma, confidenceThreshold]
    }
}

struct ProcessingStatistics {
    var averageQuality: Float = 0
    var pointCount: Int = 0
    var density: Float = 0
    var confidence: Float = 0
}

struct ProcessedPointCloud {
    let points: [Point]
    let qualityScores: [Float]
    let statistics: ProcessingStatistics
}