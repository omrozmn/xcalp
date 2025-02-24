import ARKit
import Core
import Foundation
import Metal
import MetalKit
import os.log

// MARK: - Mesh Reconstruction

extension MeshProcessor {
    
    func validateInput(points: [SIMD3<Float>]) throws {
        guard points.count >= 1000 else {
            logger.error("Insufficient points for processing: \(points.count)")
            throw MeshProcessingError.insufficientPoints
        }
        
        let density = calculatePointDensity(points)
        guard density >= MeshProcessingConfig.minimumPointDensity else {
            logger.error("Point density below threshold: \(density) points/cm²")
            throw MeshProcessingError.pointDensityInsufficient(density: density)
        }
    }
    
    func reconstructSurface(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]
    ) async throws -> MTLBuffer {
        logger.info("Starting surface reconstruction")
        
        let octree = try buildOctree(vertices: points, normals: normals)
        let meshBuffer = try await performPoissonReconstruction(octree: octree)
        
        return try meshOptimizer.optimizeMesh(meshBuffer)
    }
    
    func validateMeshQuality(_ meshBuffer: MTLBuffer) throws {
        let quality = calculateMeshQuality(meshBuffer)
        guard quality.isAcceptable else {
            logger.error("Mesh quality validation failed")
            throw MeshProcessingError.qualityValidationFailed(
                score: Float(quality.featurePreservation)
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func buildOctree(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>]
    ) throws -> Octree {
        let boundingBox = calculateBoundingBox(vertices)
        let octree = Octree(maxDepth: MeshProcessingConfig.octreeMaxDepth)
        
        for (vertex, normal) in zip(vertices, normals) {
            octree.insert(vertex, normal: normal)
        }
        
        return octree
    }
    
    private func performPoissonReconstruction(octree: Octree) async throws -> MTLBuffer {
        let equation = try PoissonEquationSolver.setup(octree: octree)
        let solution = try await solver.solve(equation: equation)
        return try extractIsoSurface(from: octree, solution: solution)
    }
    
    private func calculateBoundingBox(_ points: [SIMD3<Float>]) -> BoundingBox {
        points.reduce(BoundingBox()) { box, point in
            box.union(with: point)
        }
    }
    
    private func calculateMeshQuality(_ meshBuffer: MTLBuffer) -> MeshQualityMetrics {
        let metrics = MeshQualityCalculator.calculateMetrics(meshBuffer)
        
        logger.info("""
            Mesh quality metrics:
            - Density: \(metrics.pointDensity)
            - Completeness: \(metrics.surfaceCompleteness)
            - Noise: \(metrics.noiseLevel)
            - Features: \(metrics.featurePreservation)
            """)
        
        return metrics
    }
    
    private func extractIsoSurface(
        from octree: Octree,
        solution: [Float]
    ) throws -> MTLBuffer {
        try MarchingCubes.extractSurface(
            from: octree,
            solution: solution,
            device: device
        )
    }
}