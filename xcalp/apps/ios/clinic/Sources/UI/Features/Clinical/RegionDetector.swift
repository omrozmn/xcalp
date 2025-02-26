import Foundation
import Metal
import simd

final class RegionDetector {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let regionCompute: MTLComputePipelineState
    private let memoryManager: GPUMemoryManager
    
    private let resolution = 100
    private let regionTypes = ["hairline", "crown", "leftTemple", "rightTemple", "midScalp"]
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let regionFunction = library.makeFunction(name: "detectRegions") else {
            throw RegionError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.regionCompute = try device.makeComputePipelineState(function: regionFunction)
        self.memoryManager = GPUMemoryManager(device: device)
    }
    
    func detectRegions(in mesh: MeshData) async throws -> RegionMap {
        // Project mesh to uniform grid
        let (heightMap, curvatureMap, normalMap) = try projectToGrid(mesh)
        
        // Create output buffer for region detection
        guard let regionBuffer = device.makeBuffer(
            length: resolution * resolution * MemoryLayout<RegionMask>.stride,
            options: .storageModeShared
        ) else {
            throw RegionError.bufferCreationFailed
        }
        
        // Set up region detection parameters
        let params = RegionParams(
            hairlineThreshold: 0.5,
            crownThreshold: 0.6,
            templeThreshold: 0.4,
            blendingFactor: 0.3,
            smoothingRadius: 3
        )
        
        // Execute region detection
        try detectRegionsOnGPU(
            heightMap: heightMap,
            curvatureMap: curvatureMap,
            normalMap: normalMap,
            output: regionBuffer,
            params: params
        )
        
        // Process results
        let regions = processRegionBuffer(regionBuffer)
        
        // Extract boundaries for each region
        var boundaries: [String: [SIMD3<Float>]] = [:]
        for region in regionTypes {
            boundaries[region] = extractBoundary(
                for: region,
                from: regions,
                mesh: mesh
            )
        }
        
        // Calculate region properties
        var properties: [String: RegionProperties] = [:]
        for (region, boundary) in boundaries {
            properties[region] = calculateRegionProperties(
                boundary: boundary,
                mesh: mesh,
                curvatureMap: curvatureMap
            )
        }
        
        return RegionMap(
            boundaries: boundaries,
            properties: properties,
            confidence: calculateConfidence(regions)
        )
    }
    
    private func projectToGrid(_ mesh: MeshData) throws -> (
        heightMap: MTLBuffer,
        curvatureMap: MTLBuffer,
        normalMap: MTLBuffer
    ) {
        // Create output buffers
        guard let heightMap = device.makeBuffer(
                length: resolution * resolution * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let curvatureMap = device.makeBuffer(
                length: resolution * resolution * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let normalMap = device.makeBuffer(
                length: resolution * resolution * MemoryLayout<SIMD3<Float>>.stride,
                options: .storageModeShared
              ) else {
            throw RegionError.bufferCreationFailed
        }
        
        // Project vertices to uniform grid
        let gridCellSize = 2.0 / Float(resolution) // Assuming normalized coordinates [-1,1]
        
        for vertex in mesh.vertices {
            let x = Int((vertex.x + 1) * Float(resolution - 1) / 2)
            let y = Int((vertex.y + 1) * Float(resolution - 1) / 2)
            
            if x >= 0 && x < resolution && y >= 0 && y < resolution {
                let index = y * resolution + x
                
                // Update height map
                let heightPtr = heightMap.contents().assumingMemoryBound(to: Float.self)
                heightPtr[index] = vertex.z
                
                // Update normal map
                let normalPtr = normalMap.contents().assumingMemoryBound(to: SIMD3<Float>.self)
                normalPtr[index] = mesh.normals[mesh.vertices.firstIndex(of: vertex) ?? 0]
            }
        }
        
        // Compute curvature
        try computeCurvature(
            heightMap: heightMap,
            output: curvatureMap,
            resolution: resolution
        )
        
        return (heightMap, curvatureMap, normalMap)
    }
    
    private func detectRegionsOnGPU(
        heightMap: MTLBuffer,
        curvatureMap: MTLBuffer,
        normalMap: MTLBuffer,
        output: MTLBuffer,
        params: RegionParams
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RegionError.encodingFailed
        }
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(
            width: (resolution + 7) / 8,
            height: (resolution + 7) / 8,
            depth: 1
        )
        
        computeEncoder.setComputePipelineState(regionCompute)
        computeEncoder.setBuffer(heightMap, offset: 0, index: 0)
        computeEncoder.setBuffer(curvatureMap, offset: 0, index: 1)
        computeEncoder.setBuffer(normalMap, offset: 0, index: 2)
        computeEncoder.setBuffer(output, offset: 0, index: 3)
        computeEncoder.setBytes(&params, length: MemoryLayout<RegionParams>.stride, index: 4)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func processRegionBuffer(_ buffer: MTLBuffer) -> [[RegionMask]] {
        var regions = Array(
            repeating: Array(repeating: RegionMask(type: 0, confidence: 0),
                           count: resolution),
            count: resolution
        )
        
        let regionPtr = buffer.contents().assumingMemoryBound(to: RegionMask.self)
        
        for y in 0..<resolution {
            for x in 0..<resolution {
                regions[y][x] = regionPtr[y * resolution + x]
            }
        }
        
        return regions
    }
    
    private func extractBoundary(
        for region: String,
        from regions: [[RegionMask]],
        mesh: MeshData
    ) -> [SIMD3<Float>] {
        var boundary: [SIMD3<Float>] = []
        let regionId = getRegionId(region)
        
        // Find boundary pixels
        for y in 0..<resolution {
            for x in 0..<resolution {
                if regions[y][x].type == regionId {
                    // Check if this is a boundary pixel
                    if isBoundaryPixel(x: x, y: y, regions: regions, regionId: regionId) {
                        // Map grid coordinates back to 3D space
                        if let vertex = mapToVertex(x: x, y: y, mesh: mesh) {
                            boundary.append(vertex)
                        }
                    }
                }
            }
        }
        
        // Order boundary points to form a continuous loop
        return orderBoundaryPoints(boundary)
    }
    
    private func calculateRegionProperties(
        boundary: [SIMD3<Float>],
        mesh: MeshData,
        curvatureMap: MTLBuffer
    ) -> RegionProperties {
        let area = calculateArea(boundary)
        let centroid = calculateCentroid(boundary)
        let averageCurvature = calculateAverageCurvature(
            boundary: boundary,
            curvatureMap: curvatureMap,
            resolution: resolution
        )
        
        return RegionProperties(
            area: area,
            centroid: centroid,
            averageCurvature: averageCurvature,
            boundaryLength: calculateBoundaryLength(boundary)
        )
    }
    
    private func calculateConfidence(_ regions: [[RegionMask]]) -> Double {
        var totalConfidence = 0.0
        var count = 0
        
        for row in regions {
            for region in row where region.type != 0 {
                totalConfidence += Double(region.confidence)
                count += 1
            }
        }
        
        return count > 0 ? totalConfidence / Double(count) : 0.0
    }
    
    // Helper methods
    private func getRegionId(_ region: String) -> Int32 {
        switch region {
        case "hairline": return 1
        case "crown": return 2
        case "leftTemple": return 31
        case "rightTemple": return 32
        case "midScalp": return 4
        default: return 0
        }
    }
    
    private func isBoundaryPixel(
        x: Int,
        y: Int,
        regions: [[RegionMask]],
        regionId: Int32
    ) -> Bool {
        let neighbors = [
            (x-1, y), (x+1, y),
            (x, y-1), (x, y+1)
        ]
        
        for (nx, ny) in neighbors {
            if nx >= 0 && nx < resolution && ny >= 0 && ny < resolution {
                if regions[ny][nx].type != regionId {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func mapToVertex(
        x: Int,
        y: Int,
        mesh: MeshData
    ) -> SIMD3<Float>? {
        let normalizedX = Float(x) / Float(resolution - 1) * 2 - 1
        let normalizedY = Float(y) / Float(resolution - 1) * 2 - 1
        
        // Find closest mesh vertex
        return mesh.vertices.min(by: { v1, v2 in
            let d1 = pow(v1.x - normalizedX, 2) + pow(v1.y - normalizedY, 2)
            let d2 = pow(v2.x - normalizedX, 2) + pow(v2.y - normalizedY, 2)
            return d1 < d2
        })
    }
    
    private func orderBoundaryPoints(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return [] }
        
        var ordered = [points[0]]
        var remaining = Set(points.dropFirst())
        
        while !remaining.isEmpty {
            let last = ordered.last!
            if let next = remaining.min(by: { p1, p2 in
                distance(last, p1) < distance(last, p2)
            }) {
                ordered.append(next)
                remaining.remove(next)
            }
        }
        
        return ordered
    }
    
    private func calculateArea(_ points: [SIMD3<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }
        
        // Project points onto best-fit plane
        let (projectedPoints, _) = projectToPlane(points)
        
        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<projectedPoints.count {
            let j = (i + 1) % projectedPoints.count
            area += projectedPoints[i].x * projectedPoints[j].y
            area -= projectedPoints[j].x * projectedPoints[i].y
        }
        
        return abs(area) / 2
    }
    
    private func calculateCentroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(.zero, +) / Float(points.count)
    }
    
    private func calculateBoundaryLength(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 1 else { return 0 }
        
        var length: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            length += distance(points[i], points[j])
        }
        
        return length
    }
    
    private func projectToPlane(_ points: [SIMD3<Float>]) -> (
        points: [SIMD2<Float>],
        normal: SIMD3<Float>
    ) {
        // Calculate centroid and normal using PCA
        let centroid = calculateCentroid(points)
        let normal = calculatePlaneNormal(points, centroid: centroid)
        
        // Create basis vectors for projection
        let tangent = normalize(points[1] - points[0])
        let bitangent = normalize(cross(normal, tangent))
        
        // Project points onto plane
        let projectedPoints = points.map { point -> SIMD2<Float> in
            let relative = point - centroid
            return SIMD2<Float>(
                dot(relative, tangent),
                dot(relative, bitangent)
            )
        }
        
        return (projectedPoints, normal)
    }
    
    private func calculatePlaneNormal(
        _ points: [SIMD3<Float>],
        centroid: SIMD3<Float>
    ) -> SIMD3<Float> {
        var covariance = matrix_float3x3()
        
        for point in points {
            let diff = point - centroid
            covariance.columns.0 += diff * diff.x
            covariance.columns.1 += diff * diff.y
            covariance.columns.2 += diff * diff.z
        }
        
        covariance = covariance / Float(points.count)
        
        // Use power iteration to find smallest eigenvector
        var normal = normalize(SIMD3<Float>(1, 1, 1))
        for _ in 0..<10 {
            normal = normalize(covariance * normal)
        }
        
        return normal
    }
}

struct RegionMap {
    let boundaries: [String: [SIMD3<Float>]]
    let properties: [String: RegionProperties]
    let confidence: Double
}

struct RegionProperties {
    let area: Float
    let centroid: SIMD3<Float>
    let averageCurvature: Float
    let boundaryLength: Float
}

struct RegionParams {
    let hairlineThreshold: Float
    let crownThreshold: Float
    let templeThreshold: Float
    let blendingFactor: Float
    let smoothingRadius: Int32
}

struct RegionMask {
    let type: Int32
    let confidence: Float
}

enum RegionError: Error {
    case initializationFailed
    case bufferCreationFailed
    case encodingFailed
    case computationFailed
}