import Foundation
import Metal
import MetalKit
import ARKit
import os.log

// MARK: - Error Types

enum MeshProcessingError: Error {

    case initializationFailed
    case insufficientPoints
    case poissonSolverFailed
    case meshGenerationFailed
    case qualityValidationFailed(score: Float)
    case surfaceReconstructionFailed
    case pointDensityInsufficient(density: Float)
}

// MARK: - Quality Metrics

struct MeshQualityMetrics {

    let pointDensity: Double // points/cm²
    let surfaceCompleteness: Double // percentage
    let noiseLevel: Double // mm
    let featurePreservation: Double // percentage
    
    var isAcceptable: Bool {
        pointDensity >= MeshProcessingConfig.minimumPointDensity &&
        surfaceCompleteness >= MeshProcessingConfig.surfaceCompletenessThreshold &&
        noiseLevel <= MeshProcessingConfig.maxNoiseLevel &&
        featurePreservation >= MeshProcessingConfig.featurePreservationThreshold
    }
}

// MARK: - Configuration

enum MeshProcessingConfig {

    static let minimumPointDensity: Double = 500.0
    static let surfaceCompletenessThreshold: Double = 0.98
    static let maxNoiseLevel: Double = 0.1
    static let featurePreservationThreshold: Double = 0.95
    static let octreeMaxDepth: Int = 8
    static let smoothingIterations: Int = 3
}

// MARK: - Mesh Processor

final class MeshProcessor {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshProcessor")
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let solver: ConjugateGradientSolver
    private let meshOptimizer: MeshOptimizer?
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            logger.error("Failed to initialize Metal device or command queue")
            throw MeshProcessingError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.solver = try ConjugateGradientSolver(device: device)
        self.meshOptimizer = try? MeshOptimizer()
        
        logger.info("MeshProcessor initialized successfully")
    }
    
    // MARK: - Public Methods
    
    func processPointCloud(
        _ points: [SIMD3<Float>],
        normals: [SIMD3<Float>]
    ) async throws -> ARMeshAnchor {
        logger.info("Starting point cloud processing with \(points.count) points")
        
        try validateInput(points: points)
        
        let octree = buildOctree(vertices: points, normals: normals)
        let poissonEquation = try setupPoissonSystem(octree)
        
        let initialGuess = [Float](repeating: 0, count: poissonEquation.A.size)
        let solution = try await solver.solve(
            matrix: poissonEquation.A,
            vector: poissonEquation.b,
            initialGuess: initialGuess,
            tolerance: 1e-6,
            maxIterations: 100
        )
        
        guard let meshSolution = solution else {
            logger.error("Poisson solver failed")
            throw MeshProcessingError.poissonSolverFailed
        }
        
        octree.updateValues(with: meshSolution)
        
        guard let mesh = try extractIsoSurface(from: octree) else {
            logger.error("Failed to extract iso-surface")
            throw MeshProcessingError.surfaceReconstructionFailed
        }
        
        try validateMeshQuality(mesh)
        
        logger.info("Mesh processing completed successfully")
        return createARMeshAnchor(from: mesh)
    }
    
    // MARK: - Private Methods
    
    private func validateInput(points: [SIMD3<Float>]) throws {
        guard points.count >= 1000 else {
            logger.error("Insufficient points for processing: \(points.count)")
            throw MeshProcessingError.insufficientPoints
        }
        
        let density = calculatePointDensity(points)
        guard density >= 500.0 else {
            logger.error("Point density below threshold: \(density) points/cm²")
            throw MeshProcessingError.pointDensityInsufficient(density: density)
        }
    }
    
    private func buildOctree(vertices: [SIMD3<Float>], normals: [SIMD3<Float>]) -> Octree {
        Octree(vertices: vertices, 
               normals: normals, 
               maxDepth: MeshProcessingConfig.octreeMaxDepth)
    }
    
    private func setupPoissonSystem(_ octree: Octree) throws -> PoissonEquation {
        PoissonEquationSolver.setup(octree: octree)
    }
    
    private func extractIsoSurface(from octree: Octree) throws -> ARMeshGeometry? {
        let extractor = MarchingCubesExtractor(device: device)
        return try extractor.extract(from: octree)
    }
    
    // MARK: - Quality Assessment Methods
    
    private func validateMeshQuality(_ mesh: ARMeshGeometry) throws {
        let quality = calculateMeshQuality(mesh)
        guard quality.isAcceptable else {
            logger.error("Mesh quality validation failed: \(quality)")
            throw MeshProcessingError.qualityValidationFailed(score: Float(quality.pointDensity))
        }
    }
    
    private func calculatePointDensity(_ points: [SIMD3<Float>]) -> Double {
        // Calculate the bounding box of the point cloud
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            minZ = min(minZ, point.z)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
            maxZ = max(maxZ, point.z)
        }
        
        // Calculate the volume of the bounding box
        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)
        
        // Calculate the point density
        let pointDensity = Double(points.count) / Double(volume)
        return pointDensity
    }
    
    private func calculateMeshQuality(_ mesh: ARMeshGeometry) -> MeshQualityMetrics {
        // Calculate point density
        let vertices = Array(mesh.vertices)
        let pointDensity = calculatePointDensity(vertices)
        
        // Calculate surface completeness
        let surfaceArea = calculateMeshSurfaceArea(vertices, Array(mesh.faces))
        let expectedArea = estimateExpectedSurfaceArea(vertices)
        let surfaceCompleteness = (surfaceArea / expectedArea) * 100
        
        // Calculate noise level
        let noiseLevel = calculateNoiseLevel(vertices, Array(mesh.normals))
        
        // Calculate feature preservation
        let featurePreservation = calculateFeaturePreservation(
            vertices: vertices,
            normals: Array(mesh.normals),
            faces: Array(mesh.faces)
        )
        
        logger.info("""
            Mesh quality metrics calculated:
            - Point Density: \(pointDensity) points/cm²
            - Surface Completeness: \(surfaceCompleteness)%
            - Noise Level: \(noiseLevel)mm
            - Feature Preservation: \(featurePreservation)%
            """)
        
        return MeshQualityMetrics(
            pointDensity: pointDensity,
            surfaceCompleteness: surfaceCompleteness,
            noiseLevel: noiseLevel,
            featurePreservation: featurePreservation
        )
    }

    // MARK: - Helper Methods for Quality Calculations
    
    private func calculateMeshSurfaceArea(_ vertices: [SIMD3<Float>], _ faces: [Int32]) -> Double {
        var totalArea: Double = 0
        
        for i in stride(from: 0, to: faces.count, by: 3) {
            let v1 = vertices[Int(faces[i])]
            let v2 = vertices[Int(faces[i + 1])]
            let v3 = vertices[Int(faces[i + 2])]
            
            let edge1 = v2 - v1
            let edge2 = v3 - v1
            let triangleArea = length(cross(edge1, edge2)) * 0.5
            totalArea += Double(triangleArea)
        }
        
        return totalArea
    }

    private func estimateExpectedSurfaceArea(_ vertices: [SIMD3<Float>]) -> Double {
        // Use convex hull to estimate expected surface area
        let boundingBox = vertices.reduce(into: (min: SIMD3<Float>(repeating: .infinity),
                                               max: SIMD3<Float>(repeating: -.infinity))) { result, vertex in
            result.min = min(result.min, vertex)
            result.max = max(result.max, vertex)
        }
        
        let dimensions = boundingBox.max - boundingBox.min
        return Double(dimensions.x * dimensions.y + 
                     dimensions.y * dimensions.z + 
                     dimensions.z * dimensions.x) * 1.2 // Add 20% margin
    }

    private func calculateNoiseLevel(_ vertices: [SIMD3<Float>], _ normals: [SIMD3<Float>]) -> Double {
        var totalDeviation: Float = 0
        
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let normal = normals[i]
            
            // Find neighboring vertices
            let neighbors = findNeighborVertices(vertex, vertices, radius: 0.01) // 1cm radius
            if neighbors.isEmpty { continue }
            
            // Calculate local plane using normal
            let projectedPoints = neighbors.map { neighbor -> Float in
                let toNeighbor = neighbor - vertex
                return abs(dot(toNeighbor, normal))
            }
            
            // Calculate standard deviation from plane
            let deviation = standardDeviation(projectedPoints)
            totalDeviation += deviation
        }
        
        return Double(totalDeviation / Float(vertices.count))
    }

    private func calculateFeaturePreservation(
        vertices: [SIMD3<Float>], 
        normals: [SIMD3<Float>], 
        faces: [Int32]
    ) -> Double {
        var preservationScore: Float = 0
        var featureCount: Int = 0
        
        // Detect features using normal variation
        for i in 0..<vertices.count {
            let normal = normals[i]
            let vertex = vertices[i]
            
            // Find neighboring vertices
            let neighbors = findNeighborVertices(vertex, vertices, radius: 0.02) // 2cm radius
            if neighbors.isEmpty { continue }
            
            // Calculate normal variation
            let neighborNormals = neighbors.map { neighborVertex -> SIMD3<Float> in
                let idx = vertices.firstIndex(where: { length($0 - neighborVertex) < Float.ulpOfOne })!
                return normals[idx]
            }
            
            let normalVariation = calculateNormalVariation(normal, neighborNormals)
            
            // High normal variation indicates a feature
            if normalVariation > 0.5 {
                featureCount += 1
                
                // Check if feature is preserved in mesh
                let featurePreservation = calculateLocalFeaturePreservation(
                    at: vertex,
                    normal: normal,
                    neighbors: neighbors,
                    neighborNormals: neighborNormals
                )
                preservationScore += featurePreservation
            }
        }
        
        return featureCount > 0 ? Double(preservationScore / Float(featureCount)) * 100 : 100
    }

    private func findNeighborVertices(
        _ vertex: SIMD3<Float>, 
        _ vertices: [SIMD3<Float>], 
        radius: Float
    ) -> [SIMD3<Float>] {
        vertices.filter { neighbor in
            let distance = length(neighbor - vertex)
            return distance > Float.ulpOfOne && distance < radius
        }
    }

    private func standardDeviation(_ values: [Float]) -> Float {
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Float(values.count))
    }

    private func calculateNormalVariation(_ normal: SIMD3<Float>, _ neighborNormals: [SIMD3<Float>]) -> Float {
        let dotProducts = neighborNormals.map { abs(dot(normal, $0)) }
        return 1 - (dotProducts.reduce(0, +) / Float(neighborNormals.count))
    }

    private func calculateLocalFeaturePreservation(
        at vertex: SIMD3<Float>,
        normal: SIMD3<Float>,
        neighbors: [SIMD3<Float>],
        neighborNormals: [SIMD3<Float>]
    ) -> Float {
        // Calculate local curvature preservation
        let curvature = calculateLocalCurvature(vertex, normal, neighbors)
        
        // Calculate normal consistency
        let normalConsistency = neighborNormals.map { abs(dot(normal, $0)) }.reduce(0, +) / Float(neighborNormals.count)
        
        // Combine metrics with weights
        return curvature * 0.6 + normalConsistency * 0.4
    }

    private func calculateLocalCurvature(
        _ vertex: SIMD3<Float>, 
        _ normal: SIMD3<Float>, 
        _ neighbors: [SIMD3<Float>]
    ) -> Float {
        let projectedNeighbors = neighbors.map { neighbor -> Float in
            let toNeighbor = normalize(neighbor - vertex)
            return abs(dot(toNeighbor, normal))
        }
        
        // Calculate variance of projected distances as curvature measure
        let mean = projectedNeighbors.reduce(0, +) / Float(projectedNeighbors.count)
        let variance = projectedNeighbors.map { pow($0 - mean, 2) }.reduce(0, +) / Float(projectedNeighbors.count)
        
        return 1 - min(sqrt(variance) * 10, 1) // Normalize to [0,1]
    }
    
    private func createARMeshAnchor(from mesh: ARMeshGeometry) -> ARMeshAnchor {
        ARMeshAnchor(geometry: mesh, transform: .identity)
    }
}
