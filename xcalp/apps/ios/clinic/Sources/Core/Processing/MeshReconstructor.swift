import Foundation
import Metal
import ARKit
import Accelerate
import os.log

final class MeshReconstructor {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshReconstructor")
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let poissonSolver: PoissonSolver
    private let meshOptimizer: MeshOptimizer
    
    struct ReconstructionParameters {
        let octreeDepth: Int
        let samplesPerNode: Int
        let pointWeight: Float
        let trimThreshold: Float
        
        static let `default` = ReconstructionParameters(
            octreeDepth: 8,
            samplesPerNode: 1,
            pointWeight: 4.0,
            trimThreshold: 6.0
        )
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw MeshProcessingError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.poissonSolver = try PoissonSolver(device: device)
        self.meshOptimizer = try MeshOptimizer()
    }
    
    func reconstructFromLiDAR(_ meshGeometry: ARMeshGeometry) async throws -> MeshData {
        logger.info("Starting LiDAR mesh reconstruction")
        
        // Convert ARMeshGeometry to point cloud
        let vertices = Array(meshGeometry.vertices)
        let normals = Array(meshGeometry.normals)
        
        // Clean and prepare point cloud
        let cleanedPoints = try await removeOutliers(vertices, normals)
        
        // Perform Poisson reconstruction
        let mesh = try await poissonReconstruction(
            points: cleanedPoints.vertices,
            normals: cleanedPoints.normals
        )
        
        // Post-process and optimize mesh
        return try await postProcessMesh(mesh)
    }
    
    func reconstructFromPhotogrammetry(_ points: [PhotogrammetryPoint]) async throws -> MeshData {
        logger.info("Starting photogrammetry mesh reconstruction")
        
        // Extract position and normal data
        let positions = points.map { $0.position }
        let normals = points.map { $0.normal }
        
        // Clean point cloud
        let cleanedPoints = try await removeOutliers(positions, normals)
        
        // Perform reconstruction
        let mesh = try await poissonReconstruction(
            points: cleanedPoints.vertices,
            normals: cleanedPoints.normals,
            parameters: ReconstructionParameters(
                octreeDepth: 9, // Higher detail for photogrammetry
                samplesPerNode: 2,
                pointWeight: 5.0,
                trimThreshold: 7.0
            )
        )
        
        return try await postProcessMesh(mesh)
    }
    
    func fuseMeshes(lidarMesh: MeshData, photoMesh: MeshData) async throws -> MeshData {
        logger.info("Starting mesh fusion")
        
        // Align meshes using ICP
        let alignedPhotoMesh = try await alignMeshes(source: photoMesh, target: lidarMesh)
        
        // Merge vertex data with confidence weighting
        let fusedMesh = try await mergeMeshData(
            lidarMesh: lidarMesh,
            photoMesh: alignedPhotoMesh
        )
        
        // Optimize fused mesh
        return try await postProcessMesh(fusedMesh)
    }
    
    private func removeOutliers(_ vertices: [SIMD3<Float>], _ normals: [SIMD3<Float>]) async throws -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        let spatialIndex = SpatialIndex(points: vertices)
        var cleanedVertices: [SIMD3<Float>] = []
        var cleanedNormals: [SIMD3<Float>] = []
        
        for (idx, vertex) in vertices.enumerated() {
            let neighbors = spatialIndex.findNeighbors(for: vertex, radius: 0.01)
            
            if neighbors.count >= 3 {
                let neighborNormals = neighbors.map { normals[$0] }
                let normalConsistency = calculateNormalConsistency(normals[idx], neighborNormals)
                
                if normalConsistency > 0.7 {
                    cleanedVertices.append(vertex)
                    cleanedNormals.append(normals[idx])
                }
            }
        }
        
        return (vertices: cleanedVertices, normals: cleanedNormals)
    }
    
    private func poissonReconstruction(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        parameters: ReconstructionParameters = .default
    ) async throws -> MeshData {
        // Build octree from point cloud
        let octree = try await buildOctree(
            points: points,
            normals: normals,
            depth: parameters.octreeDepth
        )
        
        // Solve Poisson equation
        let solution = try await poissonSolver.solve(
            octree: octree,
            pointWeight: parameters.pointWeight,
            samplesPerNode: parameters.samplesPerNode
        )
        
        // Extract iso-surface
        return try await extractMesh(
            from: solution,
            octree: octree,
            trimThreshold: parameters.trimThreshold
        )
    }
    
    private func postProcessMesh(_ mesh: MeshData) async throws -> MeshData {
        // Remove small disconnected components
        var processedMesh = try await removeSmallComponents(mesh)
        
        // Fill holes
        processedMesh = try await fillHoles(processedMesh)
        
        // Optimize mesh
        processedMesh = try await meshOptimizer.optimizeMesh(processedMesh)
        
        return processedMesh
    }
    
    private func alignMeshes(source: MeshData, target: MeshData) async throws -> MeshData {
        let icp = ICPAlignment(maxIterations: 50, convergenceThreshold: 1e-6)
        let transform = try await icp.align(source: source, target: target)
        
        // Apply transformation to source mesh
        let transformedVertices = source.vertices.map { vertex in
            transformPoint(vertex, transform: transform)
        }
        
        let transformedNormals = source.normals.map { normal in
            transformNormal(normal, transform: transform)
        }
        
        return MeshData(
            vertices: transformedVertices,
            indices: source.indices,
            normals: transformedNormals,
            confidence: source.confidence
        )
    }
    
    private func mergeMeshData(lidarMesh: MeshData, photoMesh: MeshData) async throws -> MeshData {
        var mergedVertices: [SIMD3<Float>] = []
        var mergedNormals: [SIMD3<Float>] = []
        var mergedIndices: [UInt32] = []
        var mergedConfidence: [Float] = []
        
        // Use vertex clustering to merge close vertices
        let spatialIndex = SpatialIndex(points: lidarMesh.vertices)
        
        // Process LiDAR mesh vertices
        for (idx, vertex) in lidarMesh.vertices.enumerated() {
            mergedVertices.append(vertex)
            mergedNormals.append(lidarMesh.normals[idx])
            mergedConfidence.append(lidarMesh.confidence[idx])
        }
        
        // Process photogrammetry mesh vertices
        for (idx, vertex) in photoMesh.vertices.enumerated() {
            if let nearestIdx = spatialIndex.findNearest(to: vertex, maxDistance: 0.005) {
                // Merge with existing vertex using weighted average
                let weight = photoMesh.confidence[idx]
                mergedVertices[nearestIdx] = lerp(
                    mergedVertices[nearestIdx],
                    vertex,
                    t: weight
                )
                mergedNormals[nearestIdx] = normalize(
                    lerp(mergedNormals[nearestIdx],
                         photoMesh.normals[idx],
                         t: weight)
                )
                mergedConfidence[nearestIdx] = max(
                    mergedConfidence[nearestIdx],
                    photoMesh.confidence[idx]
                )
            } else {
                // Add as new vertex
                mergedVertices.append(vertex)
                mergedNormals.append(photoMesh.normals[idx])
                mergedConfidence.append(photoMesh.confidence[idx])
            }
        }
        
        // Rebuild topology
        mergedIndices = try await reconstructTopology(mergedVertices, mergedNormals)
        
        return MeshData(
            vertices: mergedVertices,
            indices: mergedIndices,
            normals: mergedNormals,
            confidence: mergedConfidence
        )
    }
    
    private func calculateNormalConsistency(_ normal: SIMD3<Float>, _ neighborNormals: [SIMD3<Float>]) -> Float {
        let consistencies = neighborNormals.map { neighborNormal in
            abs(dot(normal, neighborNormal))
        }
        return consistencies.reduce(0, +) / Float(consistencies.count)
    }
    
    private func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }
    
    private func transformPoint(_ point: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float> {
        let homogeneous = SIMD4<Float>(point.x, point.y, point.z, 1)
        let transformed = transform * homogeneous
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z) / transformed.w
    }
    
    private func transformNormal(_ normal: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float> {
        // Use inverse transpose for normal transformation
        let normalTransform = transform.inverse.transpose
        let transformed = normalTransform * SIMD4<Float>(normal.x, normal.y, normal.z, 0)
        return normalize(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
    }
}