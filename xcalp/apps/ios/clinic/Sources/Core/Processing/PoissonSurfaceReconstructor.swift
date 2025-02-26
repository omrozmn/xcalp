import Foundation
import Metal
import simd
import Accelerate

final class PoissonSurfaceReconstructor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let octree: Octree
    
    struct ReconstructionParameters {
        let depth: Int
        let samplesPerNode: Int
        let pointWeight: Float
        let scale: Float
        
        static let `default` = ReconstructionParameters(
            depth: 8,
            samplesPerNode: 1,
            pointWeight: 4.0,
            scale: 1.1
        )
    }
    
    init(device: MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else {
            throw ReconstructionError.initializationFailed
        }
        self.device = device
        self.commandQueue = queue
        self.octree = Octree(maxDepth: 8)
    }
    
    func reconstruct(from points: [OctreePoint], parameters: ReconstructionParameters = .default) async throws -> MeshData {
        // Build octree from input points
        octree.build(from: points.map { $0.position })
        
        // Setup linear system
        let (A, b) = try setupPoissonSystem(points: points, parameters: parameters)
        
        // Solve system using conjugate gradient
        let x = try await solvePoissonSystem(A: A, b: b)
        
        // Extract iso-surface using marching cubes
        let mesh = try extractIsoSurface(from: x, parameters: parameters)
        
        return mesh
    }
    
    private func setupPoissonSystem(points: [OctreePoint], parameters: ReconstructionParameters) throws -> (SparseMatrix, [Float]) {
        var A = SparseMatrix(size: octree.nodeCount)
        var b = [Float](repeating: 0, count: octree.nodeCount)
        
        // Compute vector field V from oriented points
        for point in points {
            guard let normal = point.normal else { continue }
            
            // Find nodes affected by this point
            let nodes = octree.findNodes(near: point.position, radius: parameters.scale)
            
            for node in nodes {
                // Compute basis function gradients
                let gradient = computeBasisGradient(at: point.position, node: node)
                
                // Accumulate contributions to linear system
                let weight = point.confidence * parameters.pointWeight
                A.add(at: node.index, value: dot(gradient, gradient) * weight)
                b[node.index] += dot(gradient, normal) * weight
            }
        }
        
        return (A, b)
    }
    
    private func solvePoissonSystem(A: SparseMatrix, b: [Float]) async throws -> [Float] {
        let solver = ConjugateGradientSolver(maxIterations: 1000, tolerance: 1e-6)
        return try await solver.solve(A: A, b: b)
    }
    
    private func extractIsoSurface(from solution: [Float], parameters: ReconstructionParameters) throws -> MeshData {
        let mc = MarchingCubes(device: device)
        
        // Convert solution to 3D scalar field
        let gridSize = 1 << parameters.depth
        var field = [Float](repeating: 0, count: gridSize * gridSize * gridSize)
        
        // Evaluate solution at grid points
        octree.evaluateSolution(solution, into: &field, gridSize: gridSize)
        
        // Extract surface using marching cubes
        let mesh = try mc.extract(from: field, gridSize: SIMD3<Int>(repeating: gridSize))
        
        // Transform mesh back to original scale
        return transformToWorldSpace(mesh, parameters: parameters)
    }
    
    private func computeBasisGradient(at point: SIMD3<Float>, node: OctreeNode) -> SIMD3<Float> {
        // Compute gradient of the basis function centered at node
        let diff = point - node.center
        let radius = node.size.x / 2
        
        // Use smoothed basis function gradient
        let r = length(diff) / radius
        if r >= 1 { return .zero }
        
        let scale = -3 * (1 - r * r) / (radius * radius * radius)
        return diff * scale
    }
    
    private func transformToWorldSpace(_ mesh: MeshData, parameters: ReconstructionParameters) -> MeshData {
        let scale = 1.0 / Float(1 << parameters.depth)
        let transform = simd_float4x4(scale: SIMD3<Float>(repeating: scale))
        return mesh.transformed(by: transform)
    }
}

enum ReconstructionError: Error {
    case initializationFailed
    case insufficientPoints
    case solvingFailed
    case surfaceExtractionFailed
}

// Sparse matrix implementation for the linear system
private struct SparseMatrix {
    var rows: [Int]
    var cols: [Int]
    var values: [Float]
    let size: Int
    
    init(size: Int) {
        self.size = size
        self.rows = []
        self.cols = []
        self.values = []
    }
    
    mutating func add(at index: Int, value: Float) {
        rows.append(index)
        cols.append(index)
        values.append(value)
    }
    
    func multiply(_ x: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: size)
        for (i, row) in rows.enumerated() {
            result[row] += values[i] * x[cols[i]]
        }
        return result
    }
}