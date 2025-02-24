import CoreImage
import Foundation
import simd

public final class DensityMapper {
    private let imageAnalyzer: ImageAnalyzer
    private let regionSegmenter: RegionSegmenter
    private let densityInterpolator: DensityInterpolator
    
    public init(
        imageAnalyzer: ImageAnalyzer = ImageAnalyzer(),
        regionSegmenter: RegionSegmenter = RegionSegmenter(),
        densityInterpolator: DensityInterpolator = DensityInterpolator()
    ) {
        self.imageAnalyzer = imageAnalyzer
        self.regionSegmenter = regionSegmenter
        self.densityInterpolator = densityInterpolator
    }
    
    public func generateDensityMap(
        from scan: ScanData,
        resolution: Float,
        preferences: DensityPreferences
    ) async throws -> DensityMap {
        // Analyze scan data to detect hair density
        let densityPoints = try await imageAnalyzer.analyzeDensity(
            scan: scan,
            resolution: resolution
        )
        
        // Segment regions based on density patterns
        let regions = try await regionSegmenter.segmentRegions(
            densityPoints: densityPoints,
            preferences: preferences
        )
        
        // Generate interpolated density map
        let (densityValues, maxDensity, minDensity) = try await densityInterpolator.interpolateDensity(
            points: densityPoints,
            resolution: resolution,
            regions: regions
        )
        
        // Create density regions with target densities
        let densityRegions = try createDensityRegions(
            regions: regions,
            densityValues: densityValues,
            preferences: preferences
        )
        
        return DensityMap(
            resolution: resolution,
            densityValues: densityValues,
            maxDensity: maxDensity,
            minDensity: minDensity,
            regions: densityRegions
        )
    }
    
    private func createDensityRegions(
        regions: [SegmentedRegion],
        densityValues: [[Float]],
        preferences: DensityPreferences
    ) throws -> [DensityRegion] {
        regions.map { region in
            let averageDensity = calculateAverageDensity(
                in: region,
                densityValues: densityValues
            )
            
            let targetDensity = preferences.targetDensities[region.name] ?? averageDensity
            
            return DensityRegion(
                name: region.name,
                boundaries: region.boundaries,
                averageDensity: averageDensity,
                targetDensity: targetDensity
            )
        }
    }
    
    private func calculateAverageDensity(
        in region: SegmentedRegion,
        densityValues: [[Float]]
    ) -> Float {
        // Calculate average density within region boundaries
        var sum: Float = 0
        var count = 0
        
        // Convert region boundaries to 2D coordinates
        let boundaryPoints = region.boundaries.map { point in
            (Int(point.x * Float(densityValues.count)),
             Int(point.y * Float(densityValues[0].count)))
        }
        
        // Use point-in-polygon test for each density value
        for i in 0..<densityValues.count {
            for j in 0..<densityValues[i].count {
                let point = (i, j)
                if isPointInPolygon(point, boundaryPoints) {
                    sum += densityValues[i][j]
                    count += 1
                }
            }
        }
        
        return !isEmpty ? sum / Float(count) : 0
    }
    
    private func isPointInPolygon(
        _ point: (Int, Int),
        _ polygon: [(Int, Int)]
    ) -> Bool {
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if (polygon[i].1 > point.1) != (polygon[j].1 > point.1) &&
                point.0 < (polygon[j].0 - polygon[i].0) * (point.1 - polygon[i].1) /
                (polygon[j].1 - polygon[i].1) + polygon[i].0 {
                inside.toggle()
            }
            j = i
        }
        
        return inside
    }
}

// MARK: - Supporting Types

public struct DensityPreferences {
    public let targetDensities: [String: Float]
    public let minRegionSize: Float
    public let smoothingFactor: Float
    public let densityThresholds: [Float]
    
    public init(
        targetDensities: [String: Float],
        minRegionSize: Float,
        smoothingFactor: Float,
        densityThresholds: [Float]
    ) {
        self.targetDensities = targetDensities
        self.minRegionSize = minRegionSize
        self.smoothingFactor = smoothingFactor
        self.densityThresholds = densityThresholds
    }
}

public struct DensityPoint {
    public let position: simd_float3
    public let density: Float
    public let confidence: Float
}

public struct SegmentedRegion {
    public let name: String
    public let boundaries: [simd_float3]
    public let meanDensity: Float
    public let densityVariance: Float
}

public enum DensityError: Error {
    case invalidScanData(String)
    case analysisFailure(String)
    case segmentationFailure(String)
    case interpolationFailure(String)
}

// MARK: - Supporting Classes

public final class ImageAnalyzer {
    private let ciContext: CIContext
    private let visionQueue = DispatchQueue(label: "com.xcalp.vision", qos: .userInitiated)
    
    public init() {
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
    }
    
    public func analyzeDensity(
        scan: ScanData,
        resolution: Float
    ) async throws -> [DensityPoint] {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "densityAnalysis",
            category: "treatment"
        )
        
        do {
            // Convert scan data to image for analysis
            let image = try await createAnalysisImage(from: scan)
            
            // Detect hair features using Vision framework
            let features = try await detectHairFeatures(in: image)
            
            // Convert features to density points
            let densityPoints = try await convertToDensityPoints(
                features: features,
                resolution: resolution,
                scanData: scan
            )
            
            PerformanceMonitor.shared.endMeasuring(
                "densityAnalysis",
                signpostID: perfID,
                category: "treatment"
            )
            
            return densityPoints
        } catch {
            PerformanceMonitor.shared.endMeasuring(
                "densityAnalysis",
                signpostID: perfID,
                category: "treatment",
                error: error
            )
            throw error
        }
    }
    
    private func createAnalysisImage(from scan: ScanData) async throws -> CIImage {
        // Create grayscale depth map from scan data
        let depthMap = try createDepthMap(from: scan.meshData)
        
        // Apply preprocessing filters
        let filtered = try await applyImageFilters(to: depthMap)
        
        return filtered
    }
    
    private func createDepthMap(from meshData: Data) throws -> CIImage {
        // Convert mesh vertices to depth values
        let vertices = try extractVertices(from: meshData)
        let depthValues = calculateDepthValues(from: vertices)
        
        // Create grayscale image from depth values
        let width = 512
        let height = 512
        var imageData = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let depth = depthValues[y][x]
                imageData[y * width + x] = UInt8(depth * 255)
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(data: Data(imageData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DensityError.invalidScanData("Failed to create depth map image")
        }
        
        return CIImage(cgImage: cgImage)
    }
    
    private func applyImageFilters(to image: CIImage) async throws -> CIImage {
        var filtered = image
        
        // Apply noise reduction
        if let noiseReduction = CIFilter(name: "CINoiseReduction") {
            noiseReduction.setValue(filtered, forKey: kCIInputImageKey)
            noiseReduction.setValue(0.02, forKey: "inputNoiseLevel")
            noiseReduction.setValue(0.40, forKey: "inputSharpness")
            if let output = noiseReduction.outputImage {
                filtered = output
            }
        }
        
        // Apply contrast enhancement
        if let contrast = CIFilter(name: "CIColorControls") {
            contrast.setValue(filtered, forKey: kCIInputImageKey)
            contrast.setValue(1.1, forKey: kCIInputContrastKey)
            if let output = contrast.outputImage {
                filtered = output
            }
        }
        
        return filtered
    }
    
    private func detectHairFeatures(in image: CIImage) async throws -> [VNFeatureObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFeaturesRequest()
            request.featureTypes = [.edges, .ridges]
            
            let handler = VNImageRequestHandler(ciImage: image)
            
            visionQueue.async {
                do {
                    try handler.perform([request])
                    if let results = request.results {
                        continuation.resume(returning: results)
                    } else {
                        continuation.resume(throwing: DensityError.analysisFailure("No features detected"))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func convertToDensityPoints(
        features: [VNFeatureObservation],
        resolution: Float,
        scanData: ScanData
    ) async throws -> [DensityPoint] {
        var densityPoints: [DensityPoint] = []
        
        let gridSize = Int(1.0 / resolution)
        var densityGrid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        
        // Convert feature observations to density grid
        for feature in features {
            let normalizedX = feature.boundingBox.midX
            let normalizedY = feature.boundingBox.midY
            
            let gridX = Int(normalizedX * Float(gridSize - 1))
            let gridY = Int(normalizedY * Float(gridSize - 1))
            
            if gridX >= 0 && gridX < gridSize && gridY >= 0 && gridY < gridSize {
                densityGrid[gridY][gridX] += 1
            }
        }
        
        // Convert grid to density points
        let maxCount = densityGrid.flatMap { $0 }.max() ?? 1
        
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let density = Float(densityGrid[y][x]) / Float(maxCount)
                if density > 0.1 { // Threshold to filter noise
                    let position = simd_float3(
                        Float(x) * resolution,
                        Float(y) * resolution,
                        0.0 // Z coordinate will be set from mesh data
                    )
                    
                    densityPoints.append(DensityPoint(
                        position: position,
                        density: density,
                        confidence: calculateConfidence(density: density)
                    ))
                }
            }
        }
        
        return densityPoints
    }
    
    private func calculateConfidence(density: Float) -> Float {
        // Simple confidence calculation based on density value
        // Could be enhanced with additional metrics
        min(max(density * 1.2, 0.0), 1.0)
    }
}

public final class RegionSegmenter {
    private let minimumClusterSize = 10
    private let maxIterations = 100
    
    public init() {}
    
    public func segmentRegions(
        densityPoints: [DensityPoint],
        preferences: DensityPreferences
    ) async throws -> [SegmentedRegion] {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "regionSegmentation",
            category: "treatment"
        )
        
        do {
            // Cluster points based on density and position
            let clusters = try await clusterPoints(
                densityPoints,
                thresholds: preferences.densityThresholds,
                minSize: preferences.minRegionSize
            )
            
            // Convert clusters to segmented regions
            let regions = try createSegmentedRegions(from: clusters)
            
            PerformanceMonitor.shared.endMeasuring(
                "regionSegmentation",
                signpostID: perfID,
                category: "treatment"
            )
            
            return regions
        } catch {
            PerformanceMonitor.shared.endMeasuring(
                "regionSegmentation",
                signpostID: perfID,
                category: "treatment",
                error: error
            )
            throw error
        }
    }
    
    private func clusterPoints(
        _ points: [DensityPoint],
        thresholds: [Float],
        minSize: Float
    ) async throws -> [[DensityPoint]] {
        var clusters: [[DensityPoint]] = []
        var unassignedPoints = points
        
        // Sort thresholds in descending order
        let sortedThresholds = thresholds.sorted(by: >)
        
        // Cluster for each density threshold
        for threshold in sortedThresholds {
            let densityFilteredPoints = unassignedPoints.filter { $0.density >= threshold }
            if densityFilteredPoints.isEmpty { continue }
            
            // Use DBSCAN clustering
            let newClusters = try dbscan(
                points: densityFilteredPoints,
                epsilon: minSize,
                minPoints: minimumClusterSize
            )
            
            // Add valid clusters
            for cluster in newClusters {
                if cluster.count >= minimumClusterSize {
                    clusters.append(cluster)
                    // Remove clustered points from unassigned
                    unassignedPoints.removeAll { point in
                        cluster.contains { $0.position == point.position }
                    }
                }
            }
        }
        
        return clusters
    }
    
    private func dbscan(
        points: [DensityPoint],
        epsilon: Float,
        minPoints: Int
    ) throws -> [[DensityPoint]] {
        var clusters: [[DensityPoint]] = []
        var visited = Set<Int>()
        var currentCluster: [DensityPoint] = []
        
        for (i, point) in points.enumerated() {
            if visited.contains(i) { continue }
            visited.insert(i)
            
            let neighbors = findNeighbors(of: point, in: points, epsilon: epsilon)
            
            if neighbors.count >= minPoints {
                currentCluster = [point]
                var seedSet = neighbors
                
                while !seedSet.isEmpty {
                    let currentPoint = seedSet.removeFirst()
                    let currentIndex = points.firstIndex { $0.position == currentPoint.position }!
                    
                    if !visited.contains(currentIndex) {
                        visited.insert(currentIndex)
                        let newNeighbors = findNeighbors(of: currentPoint, in: points, epsilon: epsilon)
                        
                        if newNeighbors.count >= minPoints {
                            seedSet.append(contentsOf: newNeighbors.filter { neighbor in
                                !seedSet.contains { $0.position == neighbor.position } &&
                                !currentCluster.contains { $0.position == neighbor.position }
                            })
                        }
                    }
                    
                    if !currentCluster.contains(where: { $0.position == currentPoint.position }) {
                        currentCluster.append(currentPoint)
                    }
                }
                
                if currentCluster.count >= minPoints {
                    clusters.append(currentCluster)
                }
            }
        }
        
        return clusters
    }
    
    private func findNeighbors(
        of point: DensityPoint,
        in points: [DensityPoint],
        epsilon: Float
    ) -> [DensityPoint] {
        points.filter { neighbor in
            guard neighbor.position != point.position else { return false }
            return simd_distance(neighbor.position, point.position) <= epsilon
        }
    }
    
    private func createSegmentedRegions(
        from clusters: [[DensityPoint]]
    ) throws -> [SegmentedRegion] {
        clusters.enumerated().map { index, cluster in
            let meanDensity = cluster.reduce(0) { $0 + $1.density } / Float(cluster.count)
            
            let variance = cluster.reduce(0) { sum, point in
                let diff = point.density - meanDensity
                return sum + (diff * diff)
            } / Float(cluster.count)
            
            // Create convex hull for boundaries
            let boundaries = try calculateConvexHull(for: cluster)
            
            return SegmentedRegion(
                name: "Region_\(index + 1)",
                boundaries: boundaries,
                meanDensity: meanDensity,
                densityVariance: variance
            )
        }
    }
    
    private func calculateConvexHull(
        for points: [DensityPoint]
    ) throws -> [simd_float3] {
        guard points.count >= 3 else {
            throw DensityError.segmentationFailure("Insufficient points for convex hull")
        }
        
        // Graham scan algorithm for convex hull
        let anchor = points.min { a, b in
            a.position.y < b.position.y || (a.position.y == b.position.y && a.position.x < b.position.x)
        }!
        
        let sortedPoints = points.sorted { a, b in
            let angleA = atan2(
                a.position.y - anchor.position.y,
                a.position.x - anchor.position.x
            )
            let angleB = atan2(
                b.position.y - anchor.position.y,
                b.position.x - anchor.position.x
            )
            return angleA < angleB
        }
        
        var hull: [simd_float3] = []
        for point in sortedPoints {
            while hull.count >= 2 {
                let a = hull[hull.count - 2]
                let b = hull[hull.count - 1]
                let c = point.position
                
                if crossProduct(a: a, b: b, c: c) > 0 {
                    break
                }
                hull.removeLast()
            }
            hull.append(point.position)
        }
        
        return hull
    }
    
    private func crossProduct(
        a: simd_float3,
        b: simd_float3,
        c: simd_float3
    ) -> Float {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
}

public final class DensityInterpolator {
    private let metalDevice: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    
    public init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        self.commandQueue = metalDevice?.makeCommandQueue()
    }
    
    public func interpolateDensity(
        points: [DensityPoint],
        resolution: Float,
        regions: [SegmentedRegion]
    ) async throws -> ([[Float]], Float, Float) {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "densityInterpolation",
            category: "treatment"
        )
        
        do {
            // Create grid for interpolation
            let gridSize = Int(1.0 / resolution)
            var densityGrid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
            
            // Use Metal for parallel processing if available
            if let device = metalDevice, let queue = commandQueue {
                densityGrid = try await interpolateUsingMetal(
                    points: points,
                    gridSize: gridSize,
                    device: device,
                    commandQueue: queue
                )
            } else {
                // Fallback to CPU interpolation
                densityGrid = try await interpolateUsingCPU(
                    points: points,
                    gridSize: gridSize
                )
            }
            
            // Apply regional constraints
            densityGrid = applyRegionalConstraints(
                densityGrid: densityGrid,
                regions: regions
            )
            
            // Calculate density range
            let maxDensity = densityGrid.flatMap { $0 }.max() ?? 0
            let minDensity = densityGrid.flatMap { $0 }.filter { $0 > 0 }.min() ?? 0
            
            // Apply smoothing
            let smoothedGrid = smoothDensityGrid(densityGrid)
            
            PerformanceMonitor.shared.endMeasuring(
                "densityInterpolation",
                signpostID: perfID,
                category: "treatment"
            )
            
            return (smoothedGrid, maxDensity, minDensity)
        } catch {
            PerformanceMonitor.shared.endMeasuring(
                "densityInterpolation",
                signpostID: perfID,
                category: "treatment",
                error: error
            )
            throw error
        }
    }
    
    private func interpolateUsingMetal(
        points: [DensityPoint],
        gridSize: Int,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) async throws -> [[Float]] {
        // Create buffers for input points and output grid
        guard let pointsBuffer = device.makeBuffer(
            bytes: points,
            length: points.count * MemoryLayout<DensityPoint>.stride,
            options: .storageModeShared
        ),
        let outputBuffer = device.makeBuffer(
            length: gridSize * gridSize * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw DensityError.interpolationFailure("Failed to create Metal buffers")
        }
        
        // Create and execute compute command
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw DensityError.interpolationFailure("Failed to create Metal command encoder")
        }
        
        // Set up compute pipeline
        let library = try device.makeDefaultLibrary()
        let function = try library.makeFunction(name: "interpolateDensity")
        let pipelineState = try device.makeComputePipelineState(function: function)
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(pointsBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (gridSize + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (gridSize + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Convert output buffer to grid
        let outputData = outputBuffer.contents().assumingMemoryBound(to: Float.self)
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                grid[y][x] = outputData[y * gridSize + x]
            }
        }
        
        return grid
    }
    
    private func interpolateUsingCPU(
        points: [DensityPoint],
        gridSize: Int
    ) async throws -> [[Float]] {
        var grid = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        
        // Inverse distance weighted interpolation
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let position = simd_float3(
                    Float(x) / Float(gridSize - 1),
                    Float(y) / Float(gridSize - 1),
                    0
                )
                
                var totalWeight: Float = 0
                var weightedSum: Float = 0
                
                for point in points {
                    let distance = simd_distance(position, point.position)
                    if distance < 0.001 {
                        grid[y][x] = point.density
                        break
                    }
                    
                    let weight = 1.0 / (distance * distance)
                    totalWeight += weight
                    weightedSum += weight * point.density
                }
                
                if totalWeight > 0 {
                    grid[y][x] = weightedSum / totalWeight
                }
            }
        }
        
        return grid
    }
    
    private func applyRegionalConstraints(
        densityGrid: [[Float]],
        regions: [SegmentedRegion]
    ) -> [[Float]] {
        var grid = densityGrid
        let gridSize = grid.count
        
        for region in regions {
            // Convert region boundaries to grid coordinates
            let boundaryPoints = region.boundaries.map { point in
                (
                    Int(point.x * Float(gridSize - 1)),
                    Int(point.y * Float(gridSize - 1))
                )
            }
            
            // Adjust density values within region boundaries
            for y in 0..<gridSize {
                for x in 0..<gridSize {
                    if isPointInPolygon((x, y), boundaryPoints) {
                        // Blend with region's mean density
                        grid[y][x] = (grid[y][x] + region.meanDensity) / 2
                    }
                }
            }
        }
        
        return grid
    }
    
    private func smoothDensityGrid(_ grid: [[Float]]) -> [[Float]] {
        let gridSize = grid.count
        var smoothed = Array(repeating: Array(repeating: Float(0), count: gridSize), count: gridSize)
        
        // Gaussian smoothing
        let kernel = [
            [0.0625, 0.125, 0.0625],
            [0.125, 0.25, 0.125],
            [0.0625, 0.125, 0.0625]
        ]
        
        for y in 1..<(gridSize - 1) {
            for x in 1..<(gridSize - 1) {
                var sum: Float = 0
                
                for ky in -1...1 {
                    for kx in -1...1 {
                        sum += grid[y + ky][x + kx] * Float(kernel[ky + 1][kx + 1])
                    }
                }
                
                smoothed[y][x] = sum
            }
        }
        
        // Copy edges
        for x in 0..<gridSize {
            smoothed[0][x] = grid[0][x]
            smoothed[gridSize - 1][x] = grid[gridSize - 1][x]
        }
        for y in 0..<gridSize {
            smoothed[y][0] = grid[y][0]
            smoothed[y][gridSize - 1] = grid[y][gridSize - 1]
        }
        
        return smoothed
    }
    
    private func isPointInPolygon(
        _ point: (Int, Int),
        _ polygon: [(Int, Int)]
    ) -> Bool {
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if (polygon[i].1 > point.1) != (polygon[j].1 > point.1) &&
                point.0 < (polygon[j].0 - polygon[i].0) * (point.1 - polygon[i].1) /
                (polygon[j].1 - polygon[i].1) + polygon[i].0 {
                inside.toggle()
            }
            j = i
        }
        
        return inside
    }
}
