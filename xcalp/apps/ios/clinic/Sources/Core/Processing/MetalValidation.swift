import Metal
import MetalKit
import os.log

final class MetalValidation {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MetalValidation")
    private let device: MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func validateBufferAllocation(size: Int, usage: MTLResourceOptions) -> Bool {
        let testBuffer = device.makeBuffer(length: size, options: usage)
        guard testBuffer != nil else {
            logger.error("Failed to allocate Metal buffer of size: \(size)")
            return false
        }
        return true
    }
    
    func validateComputeFunction(_ pipelineState: MTLComputePipelineState, threadCount: Int) -> Bool {
        // Check if threadgroup size is optimal
        let maxThreads = pipelineState.maxTotalThreadsPerThreadgroup
        let threadExecutionWidth = pipelineState.threadExecutionWidth
        
        if threadCount % threadExecutionWidth != 0 {
            logger.warning("Thread count \(threadCount) is not aligned with execution width \(threadExecutionWidth)")
            return false
        }
        
        // Validate memory per threadgroup
        let memoryPerThread = pipelineState.staticThreadgroupMemoryLength
        let totalMemory = memoryPerThread * threadCount
        
        if totalMemory > device.maxThreadgroupMemoryLength {
            logger.error("Required threadgroup memory \(totalMemory) exceeds device maximum \(device.maxThreadgroupMemoryLength)")
            return false
        }
        
        return true
    }
    
    func validatePointCloudProcessing(points: [Point], qualityScores: [Float]) -> ValidationResult {
        var result = ValidationResult()
        
        // Check point density
        let density = calculatePointDensity(points)
        result.densityValid = density >= 750 && density <= 1200
        
        // Check quality distribution
        let avgQuality = qualityScores.reduce(0, +) / Float(qualityScores.count)
        result.qualityValid = avgQuality >= 0.85
        
        // Check memory requirements
        let requiredMemory = points.count * (MemoryLayout<Point>.size + MemoryLayout<Float>.size)
        result.memoryValid = requiredMemory <= 150 * 1024 * 1024 // 150MB limit
        
        // Check for NaN or invalid values
        result.dataValid = !points.contains { 
            point in point.position.x.isNaN || 
                    point.position.y.isNaN || 
                    point.position.z.isNaN ||
                    point.normal.x.isNaN ||
                    point.normal.y.isNaN ||
                    point.normal.z.isNaN
        }
        
        return result
    }
    
    private func calculatePointDensity(_ points: [Point]) -> Float {
        let boundingBox = points.reduce(into: BoundingBox()) { box, point in
            box.expand(with: point.position)
        }
        
        let area = boundingBox.surfaceArea
        return Float(points.count) / (area * 10000) // Convert to points/cm²
    }
}

struct ValidationResult {
    var densityValid = false
    var qualityValid = false
    var memoryValid = false
    var dataValid = false
    
    var isValid: Bool {
        densityValid && qualityValid && memoryValid && dataValid
    }
    
    var description: String {
        """
        Validation Results:
        - Density: \(densityValid ? "✓" : "✗")
        - Quality: \(qualityValid ? "✓" : "✗")
        - Memory: \(memoryValid ? "✓" : "✗")
        - Data: \(dataValid ? "✓" : "✗")
        """
    }
}

struct BoundingBox {
    var min = SIMD3<Float>(repeating: Float.infinity)
    var max = SIMD3<Float>(repeating: -Float.infinity)
    
    mutating func expand(with point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }
    
    var surfaceArea: Float {
        let dimensions = max - min
        return 2 * (dimensions.x * dimensions.y +
                   dimensions.y * dimensions.z +
                   dimensions.z * dimensions.x)
    }
}