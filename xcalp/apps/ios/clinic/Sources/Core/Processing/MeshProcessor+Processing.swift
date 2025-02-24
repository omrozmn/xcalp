import Foundation
import SceneKit
import Metal
import simd

extension MeshProcessor {
    // MARK: - Public Methods
    
    func processPointCloud(
        _ points: [SIMD3<Float>],
        photogrammetryData: PhotogrammetryData?,
        quality: MeshQuality
    ) async throws -> SCNGeometry {
        let perfID = PerformanceMonitor.shared.startMeasuring("pointCloudProcessing")
        defer {
            PerformanceMonitor.shared.endMeasuring("pointCloudProcessing", signpostID: perfID)
        }
        
        guard !points.isEmpty else {
            throw MeshProcessingError.invalidInputData("Empty point cloud")
        }
        
        // Build octree for spatial queries
        octree = try buildOctree(from: points)
        
        // Compute oriented points with robust normal estimation
        let orientedPoints = try await computeOrientedPoints(points)
        
        guard orientedPoints.count >= ClinicalConstants.minPhotogrammetryFeatures else {
            throw MeshProcessingError.insufficientFeatures(
                found: orientedPoints.count,
                required: ClinicalConstants.minPhotogrammetryFeatures
            )
        }
        
        // Surface reconstruction using Poisson method
        var mesh = try await reconstructSurface(
            orientedPoints,
            depth: quality.poissonDepth
        )
        
        // Enhance with photogrammetry if available
        if let photoData = photogrammetryData {
            mesh = try await enhanceMeshWithPhotogrammetry(mesh, photoData)
        }
        
        // Optimize mesh while preserving features
        mesh = try await optimizeMesh(mesh)
        
        return createSCNGeometry(from: mesh)
    }
    
    // MARK: - Private Processing Methods
    
    private func buildOctree(from points: [SIMD3<Float>]) throws -> Octree {
        let perfID = PerformanceMonitor.shared.startMeasuring("octreeConstruction")
        defer {
            PerformanceMonitor.shared.endMeasuring("octreeConstruction", signpostID: perfID)
        }
        
        do {
            return try Octree(points: points, maxDepth: 8, minPointsPerNode: 8)
        } catch {
            throw MeshProcessingError.octreeConstructionFailed(error.localizedDescription)
        }
    }
    
    private func computeOrientedPoints(_ points: [SIMD3<Float>]) async throws -> [OrientedPoint] {
        if let device = device {
            return try await computeOrientedPointsGPU(points, device: device)
        }
        return try await computeOrientedPointsCPU(points)
    }
    
    private func reconstructSurface(
        _ orientedPoints: [OrientedPoint],
        depth: Int
    ) async throws -> Mesh {
        if let device = device {
            return try await performGPUReconstruction(orientedPoints, depth: depth)
        }
        return try await performCPUReconstruction(orientedPoints, depth: depth)
    }
    
    private func enhanceMeshWithPhotogrammetry(_ mesh: Mesh, _ photoData: PhotogrammetryData) async throws -> Mesh {
        let features = try await detectFeatures(mesh)
        let enhancedMesh = try await alignAndFuseMeshWithPhoto(mesh, photoData, features)
        
        // Validate quality after enhancement
        let metrics = calculateMeshMetrics(enhancedMesh)
        guard metrics.meetsMinimumRequirements() else {
            logger.warning("Enhanced mesh failed quality validation, returning original")
            return mesh
        }
        
        return enhancedMesh
    }
    
    private func optimizeMesh(_ mesh: Mesh) async throws -> Mesh {
        let perfID = PerformanceMonitor.shared.startMeasuring("meshOptimization")
        defer {
            PerformanceMonitor.shared.endMeasuring("meshOptimization", signpostID: perfID)
        }
        
        var optimizedMesh = mesh
        
        // 1. Remove outliers and noise
        optimizedMesh = try await removeOutliers(optimizedMesh)
        
        // 2. Apply adaptive Laplacian smoothing
        for _ in 0..<ClinicalConstants.laplacianIterations {
            let features = try await detectFeatures(optimizedMesh)
            optimizedMesh = try await applyAdaptiveSmoothing(
                optimizedMesh,
                features: features
            )
        }
        
        // 3. Decimate while preserving features
        optimizedMesh = try await decimateMesh(
            optimizedMesh,
            targetResolution: ClinicalConstants.meshResolutionMin
        )
        
        return optimizedMesh
    }
    
    private func createSCNGeometry(from mesh: Mesh) -> SCNGeometry {
        let vertices = mesh.vertices
        let normals = mesh.normals
        let vertexSource = SCNGeometrySource(
            vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        let normalSource = SCNGeometrySource(
            normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }
        )
        
        let element = SCNGeometryElement(
            indices: mesh.indices,
            primitiveType: .triangles
        )
        
        return SCNGeometry(
            sources: [vertexSource, normalSource],
            elements: [element]
        )
    }
}
