import Foundation
import simd

public class MeshSmoothingFilter {
    public enum SmoothingAlgorithm {
        case laplacian
        case taubin
        case hcFilter // HC-Laplacian smooth filter
    }
    
    private let iterations: Int
    private let algorithm: SmoothingAlgorithm
    private let lambda: Float
    private let mu: Float // for Taubin smoothing
    
    public init(
        algorithm: SmoothingAlgorithm = .taubin,
        iterations: Int = 3,
        lambda: Float = 0.5,
        mu: Float = -0.53
    ) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.lambda = lambda
        self.mu = mu
    }
    
    public func smoothMesh(_ vertices: [Point3D]) -> [Point3D] {
        switch algorithm {
        case .laplacian:
            return applyLaplacianSmoothing(vertices)
        case .taubin:
            return applyTaubinSmoothing(vertices)
        case .hcFilter:
            return applyHCSmoothing(vertices)
        }
    }
    
    private func applyLaplacianSmoothing(_ vertices: [Point3D]) -> [Point3D] {
        var smoothedVertices = vertices
        let spatialIndex = buildSpatialIndex(vertices)
        
        for _ in 0..<iterations {
            var newPositions = [Point3D]()
            
            for (idx, vertex) in smoothedVertices.enumerated() {
                let neighbors = findNeighbors(of: vertex, in: spatialIndex)
                if !neighbors.isEmpty {
                    let centroid = calculateCentroid(neighbors)
                    let smoothedPosition = interpolate(
                        from: vertex,
                        to: centroid,
                        factor: lambda
                    )
                    newPositions.append(smoothedPosition)
                } else {
                    newPositions.append(vertex)
                }
            }
            
            smoothedVertices = newPositions
        }
        
        return smoothedVertices
    }
    
    private func applyTaubinSmoothing(_ vertices: [Point3D]) -> [Point3D] {
        var smoothedVertices = vertices
        let spatialIndex = buildSpatialIndex(vertices)
        
        for _ in 0..<iterations {
            // Lambda step (positive)
            smoothedVertices = taubinStep(
                smoothedVertices,
                spatialIndex: spatialIndex,
                factor: lambda
            )
            
            // Mu step (negative)
            smoothedVertices = taubinStep(
                smoothedVertices,
                spatialIndex: spatialIndex,
                factor: mu
            )
        }
        
        return smoothedVertices
    }
    
    private func applyHCSmoothing(_ vertices: [Point3D]) -> [Point3D] {
        var smoothedVertices = vertices
        let spatialIndex = buildSpatialIndex(vertices)
        
        for _ in 0..<iterations {
            var newPositions = [Point3D]()
            
            for vertex in smoothedVertices {
                let neighbors = findNeighbors(of: vertex, in: spatialIndex)
                if !neighbors.isEmpty {
                    let meanCurvatureNormal = calculateMeanCurvatureNormal(
                        vertex: vertex,
                        neighbors: neighbors
                    )
                    let smoothedPosition = applyCurvatureFlow(
                        vertex: vertex,
                        curvatureNormal: meanCurvatureNormal,
                        factor: lambda
                    )
                    newPositions.append(smoothedPosition)
                } else {
                    newPositions.append(vertex)
                }
            }
            
            smoothedVertices = newPositions
        }
        
        return smoothedVertices
    }
    
    private func taubinStep(
        _ vertices: [Point3D],
        spatialIndex: [SIMD3<Float>],
        factor: Float
    ) -> [Point3D] {
        var newPositions = [Point3D]()
        
        for vertex in vertices {
            let neighbors = findNeighbors(of: vertex, in: spatialIndex)
            if !neighbors.isEmpty {
                let centroid = calculateCentroid(neighbors)
                let smoothedPosition = interpolate(
                    from: vertex,
                    to: centroid,
                    factor: factor
                )
                newPositions.append(smoothedPosition)
            } else {
                newPositions.append(vertex)
            }
        }
        
        return newPositions
    }
    
    private func buildSpatialIndex(_ vertices: [Point3D]) -> [SIMD3<Float>] {
        return vertices.map { SIMD3<Float>($0.x, $0.y, $0.z) }
    }
    
    private func findNeighbors(
        of vertex: Point3D,
        in spatialIndex: [SIMD3<Float>]
    ) -> [Point3D] {
        let searchRadius: Float = 0.01 // 1cm radius
        let vertexPosition = SIMD3<Float>(vertex.x, vertex.y, vertex.z)
        
        return spatialIndex.compactMap { neighborPosition in
            let distance = length(neighborPosition - vertexPosition)
            if distance > 0 && distance < searchRadius {
                return Point3D(
                    x: neighborPosition.x,
                    y: neighborPosition.y,
                    z: neighborPosition.z
                )
            }
            return nil
        }
    }
    
    private func calculateCentroid(_ points: [Point3D]) -> Point3D {
        let sum = points.reduce(SIMD3<Float>(0, 0, 0)) { result, point in
            result + SIMD3<Float>(point.x, point.y, point.z)
        }
        let count = Float(points.count)
        
        return Point3D(
            x: sum.x / count,
            y: sum.y / count,
            z: sum.z / count
        )
    }
    
    private func interpolate(
        from start: Point3D,
        to end: Point3D,
        factor: Float
    ) -> Point3D {
        return Point3D(
            x: start.x + (end.x - start.x) * factor,
            y: start.y + (end.y - start.y) * factor,
            z: start.z + (end.z - start.z) * factor
        )
    }
    
    private func calculateMeanCurvatureNormal(
        vertex: Point3D,
        neighbors: [Point3D]
    ) -> SIMD3<Float> {
        let vertexPosition = SIMD3<Float>(vertex.x, vertex.y, vertex.z)
        var curvatureNormal = SIMD3<Float>(0, 0, 0)
        var totalWeight: Float = 0
        
        for neighbor in neighbors {
            let neighborPosition = SIMD3<Float>(neighbor.x, neighbor.y, neighbor.z)
            let diff = neighborPosition - vertexPosition
            let distance = length(diff)
            
            if distance > 0 {
                let weight = 1.0 / distance
                curvatureNormal += weight * diff
                totalWeight += weight
            }
        }
        
        if totalWeight > 0 {
            curvatureNormal /= totalWeight
        }
        
        return curvatureNormal
    }
    
    private func applyCurvatureFlow(
        vertex: Point3D,
        curvatureNormal: SIMD3<Float>,
        factor: Float
    ) -> Point3D {
        let position = SIMD3<Float>(vertex.x, vertex.y, vertex.z)
        let newPosition = position + factor * curvatureNormal
        
        return Point3D(
            x: newPosition.x,
            y: newPosition.y,
            z: newPosition.z
        )
    }
}