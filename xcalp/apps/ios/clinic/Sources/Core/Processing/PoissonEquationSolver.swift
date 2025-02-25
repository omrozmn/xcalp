import Foundation
import simd

class PoissonEquationSolver {
    static func setup(octree: Octree) throws -> PoissonEquation {
        let nodes = getAllNodes(from: octree.root)
        
        // Number of nodes
        let n = nodes.count

        // Data structures for the sparse matrix
        var values: [Float] = []
        var columnIndices: [Int] = []
        var rowPointers: [Int] = [0] // Start with 0

        // Vector b for the Poisson equation
        var b: [Float] = [Float](repeating: 0.0, count: n)

        // Iterate through the nodes and set up the sparse matrix and vector
        var currentRowIndex = 0
        for i in 0..<n {
            let node = nodes[i]

            // Calculate the Laplacian operator at the current node
            let laplacian = calculateLaplacian(at: node, nodes: nodes, octree: octree)

            // Set the diagonal element of the sparse matrix to the Laplacian value
            values.append(laplacian)
            columnIndices.append(i)
            currentRowIndex += 1

            // Set the corresponding element of the vector to the boundary condition at the current node
            b[i] = calculateBoundaryCondition(at: node)

            // Add connections to neighboring nodes
            if let neighbors = getNeighbors(of: node, in: nodes, octree: octree) {
                for neighborIndex in neighbors {
                    // Add off-diagonal elements to the sparse matrix
                    values.append(-1.0) // Example value, adjust as needed
                    columnIndices.append(neighborIndex)
                    currentRowIndex += 1
                }
            }
            rowPointers.append(currentRowIndex)
        }

        let A = SparseMatrix(values: values, columnIndices: columnIndices, rowPointers: rowPointers, size: n)
        return PoissonEquation(A: A, b: b)
    }

    // Helper function to get all nodes from the octree
    private static func getAllNodes(from node: OctreeNode) -> [OctreeNode] {
        var nodes: [OctreeNode] = [node]
        if let children = node.children {
            for child in children {
                nodes.append(contentsOf: getAllNodes(from: child))
            }
        }
        return nodes
    }

    // Function to calculate the Laplacian operator at a given node
    private static func calculateLaplacian(at node: OctreeNode, nodes: [OctreeNode], octree: Octree) -> Float {
        guard let point = node.point else {
            return 0.0
        }

        let neighbors = getNeighbors(of: node, in: nodes, octree: octree)
        guard let neighbors = neighbors, !neighbors.isEmpty else {
            return 0.0
        }

        var laplacian: Float = 0.0
        for neighborIndex in neighbors {
            let neighbor = nodes[neighborIndex]
            if let neighborPoint = neighbor.point {
                laplacian += simd_distance(point, neighborPoint)
            }
        }

        return laplacian
    }

    // Function to calculate the boundary condition at a given node
    private static func calculateBoundaryCondition(at node: OctreeNode) -> Float {
        // Assuming the boundary condition is 0
        return 0.0
    }

    private static func getNeighbors(of node: OctreeNode, in nodes: [OctreeNode], octree: Octree) -> [Int]? {
        var neighborIndices: [Int] = []
        for i in 0..<nodes.count {
            if nodes[i] !== node {
                neighborIndices.append(i)
            }
        }
        return neighborIndices
    }

    static func solve(poissonEquation: PoissonEquation, initialGuess: [Float], tolerance: Float, maxIterations: Int) -> [Float]? {
        let A = poissonEquation.A
        let b = poissonEquation.b
        
        // Define the matrix-vector product function A(x)
        let Ax: (([Double]) -> [Double]) = { x in
            do {
                let xFloat = x.map { Float($0) }
                let resultFloat = try A.multiply(vector: xFloat)
                return resultFloat.map { Double($0) }
            } catch {
                print("Error multiplying sparse matrix with vector: \(error)")
                return [Double](repeating: 0.0, count: A.size)
            }
        }
        
        // Use the ConjugateGradientSolver to solve the system
        let solver = ConjugateGradientSolver()
        if let solution = solver.solve(A: Ax,
                                        b: b.map { Double($0) },
                                        x0: initialGuess.map { Double($0) },
                                        tolerance: Double(tolerance),
                                        maxIterations: maxIterations) {
            return solution.map { Float($0) }
        } else {
            print("Conjugate Gradient solver failed to converge.")
            return nil
        }
    }
}

struct PoissonEquation {
    let A: SparseMatrix
    let b: [Float]
}

struct SparseMatrix {
    let values: [Float]
    let columnIndices: [Int]
    let rowPointers: [Int]
    let size: Int

    func multiply(vector: [Float]) throws -> [Float] {
        guard vector.count == size else {
            throw SolverError.invalidVectorSize
        }

        var result = [Float](repeating: 0.0, count: size)
        for row in 0..<size {
            var sum: Float = 0.0
            for i in rowPointers[row]..<rowPointers[row+1] {
                let col = columnIndices[i]
                sum += values[i] * vector[col]
            }
            result[row] = sum
        }
        return result
    }
}

enum SolverError: Error {
    case commandQueueCreationFailed
    case pipelineStateCreationFailed
    case invalidVectorSize
    case maxIterationsReached
}
