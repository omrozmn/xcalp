import Foundation
import simd

public final class MeshAnalyzer {
    private let curvatureAnalyzer: CurvatureAnalyzer
    
    public init(curvatureAnalyzer: CurvatureAnalyzer = CurvatureAnalyzer()) {
        self.curvatureAnalyzer = curvatureAnalyzer
    }
    
    public func analyzeMesh(_ data: Data) async throws -> MeshMetrics {
        // Convert raw data to mesh
        let meshConverter = MeshConverter()
        let mesh = try meshConverter.convert(data)
        
        // Analyze curvature
        let curvatureMap = try await curvatureAnalyzer.analyzeCurvature(mesh)
        
        // Calculate surface area
        let totalArea = calculateSurfaceArea(mesh)
        
        // Calculate average thickness
        let averageThickness = calculateAverageThickness(mesh)
        
        // Analyze mesh quality
        let quality = analyzeQuality(mesh)
        
        return MeshMetrics(
            totalArea: totalArea,
            averageThickness: averageThickness,
            quality: quality,
            curvatureMap: curvatureMap
        )
    }
    
    private func calculateSurfaceArea(_ mesh: MeshData) -> Float {
        var totalArea: Float = 0
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            totalArea += triangleArea(v1, v2, v3)
        }
        
        return totalArea
    }
    
    private func calculateAverageThickness(_ mesh: MeshData) -> Float {
        // Use ray casting to measure thickness at sample points
        let sampleCount = 100
        var totalThickness: Float = 0
        var validSamples = 0
        
        for i in 0..<sampleCount {
            if let thickness = measureThicknessAtPoint(
                mesh.vertices[i * mesh.vertices.count / sampleCount],
                normal: mesh.normals[i * mesh.normals.count / sampleCount],
                mesh: mesh
            ) {
                totalThickness += thickness
                validSamples += 1
            }
        }
        
        return validSamples > 0 ? totalThickness / Float(validSamples) : 0
    }
    
    private func measureThicknessAtPoint(_ point: SIMD3<Float>, normal: SIMD3<Float>, mesh: MeshData) -> Float? {
        // Cast ray in normal direction and find intersection
        let ray = Ray(origin: point, direction: normal)
        let maxDistance: Float = 20 // mm
        
        var nearestHit: Float?
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            if let hit = rayTriangleIntersection(ray, v1, v2, v3),
               hit > 0.1 && hit < maxDistance { // Avoid self-intersection
                if nearestHit == nil || hit < nearestHit! {
                    nearestHit = hit
                }
            }
        }
        
        return nearestHit
    }
    
    private func analyzeQuality(_ mesh: MeshData) -> MeshQuality {
        let vertexDensity = Float(mesh.vertices.count) / calculateSurfaceArea(mesh)
        let normalConsistency = calculateNormalConsistency(mesh)
        let triangleQuality = calculateTriangleQuality(mesh)
        
        return MeshQuality(
            vertexDensity: vertexDensity,
            normalConsistency: normalConsistency,
            triangleQuality: triangleQuality
        )
    }
    
    private func calculateNormalConsistency(_ mesh: MeshData) -> Float {
        var totalConsistency: Float = 0
        var comparisons = 0
        
        // Compare each normal with its neighbors
        for i in 0..<mesh.vertices.count {
            let normal = mesh.normals[i]
            let neighbors = findNeighborIndices(for: i, in: mesh)
            
            for neighborIndex in neighbors {
                let neighborNormal = mesh.normals[neighborIndex]
                totalConsistency += abs(dot(normal, neighborNormal))
                comparisons += 1
            }
        }
        
        return comparisons > 0 ? totalConsistency / Float(comparisons) : 1
    }
    
    private func calculateTriangleQuality(_ mesh: MeshData) -> Float {
        var totalQuality: Float = 0
        let triangleCount = mesh.indices.count / 3
        
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            totalQuality += calculateTriangleMetric(v1, v2, v3)
        }
        
        return totalQuality / Float(triangleCount)
    }
    
    private func findNeighborIndices(for vertexIndex: Int, in mesh: MeshData) -> [Int] {
        var neighbors = Set<Int>()
        
        // Find vertices that share triangles with this vertex
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let indices = [
                Int(mesh.indices[i]),
                Int(mesh.indices[i + 1]),
                Int(mesh.indices[i + 2])
            ]
            
            if indices.contains(vertexIndex) {
                neighbors.formUnion(indices)
            }
        }
        
        neighbors.remove(vertexIndex)
        return Array(neighbors)
    }
    
    private func triangleArea(_ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>) -> Float {
        let cross = cross((v2 - v1), (v3 - v1))
        return length(cross) / 2
    }
    
    private func calculateTriangleMetric(_ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>) -> Float {
        // Calculate triangle quality based on aspect ratio
        let a = length(v2 - v1)
        let b = length(v3 - v2)
        let c = length(v1 - v3)
        
        let s = (a + b + c) / 2 // Semi-perimeter
        let area = sqrt(s * (s - a) * (s - b) * (s - c))
        
        // Quality metric based on ratio of area to perimeter
        return 4 * sqrt(3) * area / (a * b * c)
    }
}

public struct MeshMetrics {
    public let totalArea: Float
    public let averageThickness: Float
    public let quality: MeshQuality
    public let curvatureMap: [[Float]]
}

public struct MeshQuality {
    public let vertexDensity: Float
    public let normalConsistency: Float
    public let triangleQuality: Float
}

private struct Ray {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
}

private func rayTriangleIntersection(_ ray: Ray, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>) -> Float? {
    let edge1 = v2 - v1
    let edge2 = v3 - v1
    let h = cross(ray.direction, edge2)
    let a = dot(edge1, h)
    
    if abs(a) < 1e-6 { return nil }
    
    let f = 1.0 / a
    let s = ray.origin - v1
    let u = f * dot(s, h)
    
    if u < 0.0 || u > 1.0 { return nil }
    
    let q = cross(s, edge1)
    let v = f * dot(ray.direction, q)
    
    if v < 0.0 || u + v > 1.0 { return nil }
    
    let t = f * dot(edge2, q)
    return t > 0 ? t : nil
}