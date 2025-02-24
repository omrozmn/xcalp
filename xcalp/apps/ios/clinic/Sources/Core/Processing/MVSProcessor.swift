import CoreImage
import Foundation
import Metal

class MVSProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let patchMatch: PatchMatchMVS
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw MVSError.metalInitializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.patchMatch = try PatchMatchMVS(device: device)
    }
    
    func reconstructDense(sparseCloud: SparseCloud, depthMap: CVPixelBuffer?) throws -> PointCloud {
        // Initialize depth maps
        var depthMaps: [DepthMap] = []
        
        // If we have LiDAR depth map, use it as initial estimate
        if let lidarDepth = depthMap {
            depthMaps.append(try initializeFromLiDAR(lidarDepth))
        }
        
        // Perform multi-view stereo using PatchMatch
        let denseCloud = try patchMatch.process(
            sparseCloud: sparseCloud,
            initialDepthMaps: depthMaps,
            options: MVSOptions(
                numPhotometricConsistencySteps: 5,
                minPhotometricConsistency: 0.7,
                maxDepthDeviation: ClinicalConstants.maxDepthDeviation
            )
        )
        
        // Filter and fuse depth maps
        return try fuseDenseCloud(
            denseCloud,
            confidence: calculateMVSConfidence(denseCloud)
        )
    }
    
    private func initializeFromLiDAR(_ depthMap: CVPixelBuffer) throws -> DepthMap {
        // Convert LiDAR depth to MVS format
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        var convertedDepth = DepthMap(width: width, height: height)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            throw MVSError.depthMapConversionFailed
        }
        
        // Copy and scale depth values
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
                let depth = baseAddress.load(fromByteOffset: offset, as: Float.self)
                convertedDepth[x, y] = depth
            }
        }
        
        return convertedDepth
    }
    
    private func calculateMVSConfidence(_ cloud: PointCloud) -> Float {
        // Calculate confidence based on photometric consistency
        let consistencyScores = cloud.points.map { $0.photometricConsistency }
        return consistencyScores.reduce(0, +) / Float(consistencyScores.count)
    }
}

// Error handling
enum MVSError: Error {
    case metalInitializationFailed
    case depthMapConversionFailed
    case patchMatchFailed
    case fusionFailed
}

// Supporting types
struct MVSOptions {
    let numPhotometricConsistencySteps: Int
    let minPhotometricConsistency: Float
    let maxDepthDeviation: Float
}
