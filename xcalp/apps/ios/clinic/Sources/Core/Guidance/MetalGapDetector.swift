import Metal
import MetalKit
import CoreImage

class MetalGapDetector {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    
    init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "detectGapsKernel") else {
            throw GuidanceError.metalInitializationFailed
        }
        
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        
        guard let cache = textureCache else {
            throw GuidanceError.textureCacheCreationFailed
        }
        self.textureCache = cache
    }
    
    func detectGaps(in depthMap: CVPixelBuffer, threshold: Float = 0.05) -> [CoverageGap] {
        autoreleasepool {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let gapTexture = createGapTexture(
                    width: CVPixelBufferGetWidth(depthMap),
                    height: CVPixelBufferGetHeight(depthMap)
                  ),
                  let depthTexture = createMetalTexture(from: depthMap) else {
                return []
            }
            
            let thresholdBuffer = device.makeBuffer(
                bytes: &threshold,
                length: MemoryLayout<Float>.size,
                options: .storageModeShared
            )
            
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
                  let thresholdBuffer = thresholdBuffer else {
                return []
            }
            
            // Configure compute pipeline
            computeEncoder.setComputePipelineState(pipelineState)
            computeEncoder.setTexture(depthTexture, index: 0)
            computeEncoder.setTexture(gapTexture, index: 1)
            computeEncoder.setBuffer(thresholdBuffer, offset: 0, index: 0)
            
            // Calculate grid size
            let width = depthTexture.width
            let height = depthTexture.height
            let threadsPerThreadgroup = MTLSizeMake(8, 8, 1)
            let threadgroupsPerGrid = MTLSizeMake(
                (width + 7) / 8,
                (height + 7) / 8,
                1
            )
            
            computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // Process results
            return processGapResults(gapTexture)
        }
    }
    
    private func createGapTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.pixelFormat = .r32Float
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        return device.makeTexture(descriptor: descriptor)
    }
    
    private func createMetalTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r32Float,
            width,
            height,
            0,
            &cvTexture
        )
        
        return CVMetalTextureGetTexture(cvTexture!)
    }
    
    private func processGapResults(_ texture: MTLTexture) -> [CoverageGap] {
        var gaps: [CoverageGap] = []
        let width = texture.width
        let height = texture.height
        
        // Extract gap data
        let bytesPerRow = width * MemoryLayout<Float>.size
        var data = [Float](repeating: 0, count: width * height)
        
        texture.getBytes(
            &data,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        
        // Process connected components
        var visited = Set<CGPoint>()
        
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: x, y: y)
                if data[y * width + x] > 0.5 && !visited.contains(point) {
                    let gap = floodFill(from: point, in: data, width: width, height: height, visited: &visited)
                    gaps.append(gap)
                }
            }
        }
        
        return gaps
    }
    
    private func floodFill(
        from start: CGPoint,
        in data: [Float],
        width: Int,
        height: Int,
        visited: inout Set<CGPoint>
    ) -> CoverageGap {
        var points: Set<CGPoint> = []
        var queue = [start]
        var minX = start.x
        var minY = start.y
        var maxX = start.x
        var maxY = start.y
        
        while !queue.isEmpty {
            let point = queue.removeFirst()
            if visited.contains(point) { continue }
            
            visited.insert(point)
            points.insert(point)
            
            // Update bounds
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
            
            // Check neighbors
            let neighbors = [
                CGPoint(x: point.x - 1, y: point.y),
                CGPoint(x: point.x + 1, y: point.y),
                CGPoint(x: point.x, y: point.y - 1),
                CGPoint(x: point.x, y: point.y + 1)
            ]
            
            for neighbor in neighbors {
                if isValid(neighbor, width: width, height: height, data: data) {
                    queue.append(neighbor)
                }
            }
        }
        
        return CoverageGap(
            bounds: CGRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            ),
            averageDepth: calculateAverageDepth(points: points, data: data, width: width),
            confidence: calculateGapConfidence(points: points)
        )
    }
    
    private func isValid(_ point: CGPoint, width: Int, height: Int, data: [Float]) -> Bool {
        guard point.x >= 0 && point.x < width &&
              point.y >= 0 && point.y < height else {
            return false
        }
        
        let index = Int(point.y) * width + Int(point.x)
        return data[index] > 0.5
    }
    
    private func calculateAverageDepth(points: Set<CGPoint>, data: [Float], width: Int) -> Float {
        let sum = points.reduce(0.0) { $0 + data[Int($1.y) * width + Int($1.x)] }
        return Float(sum) / Float(points.count)
    }
    
    private func calculateGapConfidence(points: Set<CGPoint>) -> Float {
        // More sophisticated confidence calculation based on gap size and shape
        let area = Float(points.count)
        let shape = calculateShapeRegularity(points)
        return min(area / 100.0, 1.0) * shape
    }
    
    private func calculateShapeRegularity(_ points: Set<CGPoint>) -> Float {
        // Calculate how regular (circular/rectangular) the gap shape is
        // This is a simplified implementation
        let perimeter = calculatePerimeter(points)
        let area = Float(points.count)
        let circularityRatio = (4.0 * .pi * area) / (perimeter * perimeter)
        return Float(circularityRatio)
    }
    
    private func calculatePerimeter(_ points: Set<CGPoint>) -> Float {
        var perimeter: Float = 0
        for point in points {
            let neighbors = [
                CGPoint(x: point.x - 1, y: point.y),
                CGPoint(x: point.x + 1, y: point.y),
                CGPoint(x: point.x, y: point.y - 1),
                CGPoint(x: point.x, y: point.y + 1)
            ]
            
            for neighbor in neighbors {
                if !points.contains(neighbor) {
                    perimeter += 1
                }
            }
        }
        return perimeter
    }
}