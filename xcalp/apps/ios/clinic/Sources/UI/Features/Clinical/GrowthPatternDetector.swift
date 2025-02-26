import Foundation
import Metal
import CoreML
import simd

final class GrowthPatternDetector {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let curvaturePipeline: MTLComputePipelineState?
    private let landmarkPipeline: MTLComputePipelineState?
    private let regionPipeline: MTLComputePipelineState?
    
    private let maxLandmarks = 50
    private let resolution = 100
    
    init() {
        // Initialize Metal
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        
        // Create compute pipelines
        if let device = device,
           let library = try? device.makeDefaultLibrary() {
            self.curvaturePipeline = try? device.makeComputePipelineState(
                function: library.makeFunction(name: "computeCurvature")!
            )
            self.landmarkPipeline = try? device.makeComputePipelineState(
                function: library.makeFunction(name: "detectLandmarks")!
            )
            self.regionPipeline = try? device.makeComputePipelineState(
                function: library.makeFunction(name: "detectRegions")!
            )
        } else {
            self.curvaturePipeline = nil
            self.landmarkPipeline = nil
            self.regionPipeline = nil
        }
    }
    
    func detectPattern(_ curvature: [[Float]]) async throws -> GrowthPattern {
        guard let device = device,
              let commandQueue = commandQueue,
              let curvaturePipeline = curvaturePipeline,
              let landmarkPipeline = landmarkPipeline,
              let regionPipeline = regionPipeline else {
            throw DetectionError.gpuNotAvailable
        }
        
        // Create Metal buffers
        let curvatureBuffer = createBuffer(from: curvature, device: device)
        let landmarkBuffer = device.makeBuffer(
            length: MemoryLayout<Landmark>.stride * maxLandmarks,
            options: .storageModeShared
        )
        let landmarkCountBuffer = device.makeBuffer(
            length: MemoryLayout<Int32>.size,
            options: .storageModeShared
        )
        let regionBuffer = device.makeBuffer(
            length: resolution * resolution * MemoryLayout<RegionMask>.stride,
            options: .storageModeShared
        )
        
        guard let curvatureBuffer = curvatureBuffer,
              let landmarkBuffer = landmarkBuffer,
              let landmarkCountBuffer = landmarkCountBuffer,
              let regionBuffer = regionBuffer else {
            throw DetectionError.bufferCreationFailed
        }
        
        // Reset landmark count
        let countPtr = landmarkCountBuffer.contents().assumingMemoryBound(to: Int32.self)
        countPtr.pointee = 0
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DetectionError.commandEncodingFailed
        }
        
        // Configure compute kernels
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (resolution + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (resolution + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        // Execute landmark detection
        let params = LandmarkParams(
            crownThreshold: 0.7,
            templeThreshold: 0.6,
            napeThreshold: 0.5,
            whirlThreshold: 0.8,
            windowSize: 5,
            minDistance: 10.0
        )
        
        computeEncoder.setComputePipelineState(landmarkPipeline)
        computeEncoder.setBuffer(curvatureBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(landmarkBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(landmarkCountBuffer, offset: 0, index: 2)
        computeEncoder.setBytes(&params, length: MemoryLayout<LandmarkParams>.size, index: 3)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        
        // Execute region detection
        let regionParams = RegionParams(
            hairlineThreshold: 0.5,
            crownThreshold: 0.6,
            templeThreshold: 0.4,
            blendingFactor: 0.3,
            smoothingRadius: 3
        )
        
        computeEncoder.setComputePipelineState(regionPipeline)
        computeEncoder.setBuffer(curvatureBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(regionBuffer, offset: 0, index: 1)
        computeEncoder.setBytes(&regionParams, length: MemoryLayout<RegionParams>.size, index: 2)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Process results
        let landmarks = processLandmarks(buffer: landmarkBuffer, count: Int(countPtr.pointee))
        let regions = processRegions(buffer: regionBuffer)
        
        // Analyze pattern using landmarks and regions
        return try analyzeGrowthPattern(landmarks: landmarks, regions: regions)
    }
    
    private func createBuffer(from array: [[Float]], device: MTLDevice) -> MTLBuffer? {
        let flatArray = array.flatMap { $0 }
        return device.makeBuffer(
            bytes: flatArray,
            length: flatArray.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }
    
    private func processLandmarks(buffer: MTLBuffer, count: Int) -> [Landmark] {
        let landmarkPtr = buffer.contents().assumingMemoryBound(to: Landmark.self)
        return Array(UnsafeBufferPointer(start: landmarkPtr, count: count))
    }
    
    private func processRegions(buffer: MTLBuffer) -> [RegionMask] {
        let regionPtr = buffer.contents().assumingMemoryBound(to: RegionMask.self)
        return Array(UnsafeBufferPointer(start: regionPtr, count: resolution * resolution))
    }
    
    private func analyzeGrowthPattern(
        landmarks: [Landmark],
        regions: [RegionMask]
    ) throws -> GrowthPattern {
        // Find dominant growth direction using landmarks
        var primaryDirection = SIMD3<Float>.zero
        var totalWeight: Float = 0
        
        for landmark in landmarks {
            let weight = landmark.confidence
            primaryDirection += landmark.position * weight
            totalWeight += weight
        }
        
        guard totalWeight > 0 else {
            throw DetectionError.insufficientFeatures
        }
        
        primaryDirection = normalize(primaryDirection / totalWeight)
        
        // Calculate pattern variance
        let variance = calculatePatternVariance(
            primaryDirection: primaryDirection,
            landmarks: landmarks,
            regions: regions
        )
        
        // Calculate pattern significance
        let significance = calculatePatternSignificance(
            landmarks: landmarks,
            regions: regions
        )
        
        return GrowthPattern(
            direction: primaryDirection,
            significance: significance,
            variance: variance
        )
    }
    
    private func calculatePatternVariance(
        primaryDirection: SIMD3<Float>,
        landmarks: [Landmark],
        regions: [RegionMask]
    ) -> Float {
        var totalVariance: Float = 0
        var totalWeight: Float = 0
        
        for landmark in landmarks {
            let weight = landmark.confidence
            let angle = acos(abs(dot(normalize(landmark.position), primaryDirection)))
            totalVariance += angle * weight
            totalWeight += weight
        }
        
        return totalWeight > 0 ? totalVariance / totalWeight : 0.2
    }
    
    private func calculatePatternSignificance(
        landmarks: [Landmark],
        regions: [RegionMask]
    ) -> Double {
        // Calculate pattern coherence based on landmark distribution
        let landmarkSignificance = landmarks.reduce(0.0) { sum, landmark in
            sum + Double(landmark.confidence)
        } / Double(max(1, landmarks.count))
        
        // Calculate regional coherence
        let regionSignificance = regions.reduce(0.0) { sum, region in
            sum + Double(region.confidence)
        } / Double(regions.count)
        
        return 0.7 * landmarkSignificance + 0.3 * regionSignificance
    }
}

private struct LandmarkParams {
    let crownThreshold: Float
    let templeThreshold: Float
    let napeThreshold: Float
    let whirlThreshold: Float
    let windowSize: Int32
    let minDistance: Float
}

private struct RegionParams {
    let hairlineThreshold: Float
    let crownThreshold: Float
    let templeThreshold: Float
    let blendingFactor: Float
    let smoothingRadius: Int32
}

enum DetectionError: Error {
    case gpuNotAvailable
    case bufferCreationFailed
    case commandEncodingFailed
    case insufficientFeatures
}