import SceneKit
import simd

class MeshGenerator {
    private let smoothingFactor: Float = 0.5
    private let minimumTriangleSize: Float = 0.002 // 2mm minimum triangle size
    
    func generateMesh(from points: [simd_float3]) -> SCNGeometry? {
        guard points.count >= 3 else { return nil }
        
        // Create vertices source
        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        // Generate triangles using surface reconstruction
        guard let indices = generateTriangles(from: points) else { return nil }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        
        // Create normals
        guard let normalSource = generateNormals(vertices: vertices, indices: indices) else { return nil }
        
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }
    
    private func generateTriangles(from points: [simd_float3]) -> [Int32]? {
        var triangles: [Int32] = []
        
        // Implementation of Ball-Pivoting Algorithm for surface reconstruction
        // This is a simplified version - real implementation would be more complex
        
        // 1. Find seed triangle
        if let seedTriangle = findSeedTriangle(in: points) {
            triangles.append(contentsOf: seedTriangle)
            
            // 2. Expand mesh from seed triangle
            var processedEdges = Set<Edge>()
            var edgesToProcess = getTriangleEdges(seedTriangle)
            
            while let edge = edgesToProcess.popFirst() {
                guard !processedEdges.contains(edge) else { continue }
                processedEdges.insert(edge)
                
                if let newTriangle = findNextTriangle(edge: edge, points: points, existingTriangles: triangles) {
                    triangles.append(contentsOf: newTriangle)
                    edgesToProcess.formUnion(getTriangleEdges(newTriangle))
                }
            }
        }
        
        return triangles.isEmpty ? nil : triangles
    }
    
    private func findSeedTriangle(in points: [simd_float3]) -> [Int32]? {
        // Find three closest points that form a valid triangle
        guard points.count >= 3 else { return nil }
        
        for i in 0..<points.count {
            let p1 = points[i]
            var closest = [(index: Int, distance: Float)]()
            
            for j in 0..<points.count where j != i {
                let dist = distance(p1, points[j])
                closest.append((j, dist))
            }
            
            closest.sort { $0.distance < $1.distance }
            
            // Try to form triangle with two closest points
            if closest.count >= 2 {
                let j = closest[0].index
                let k = closest[1].index
                
                let triangle = [Int32(i), Int32(j), Int32(k)]
                if isValidTriangle(points[i], points[j], points[k]) {
                    return triangle
                }
            }
        }
        
        return nil
    }
    
    private func isValidTriangle(_ p1: simd_float3, _ p2: simd_float3, _ p3: simd_float3) -> Bool {
        let edge1 = distance(p1, p2)
        let edge2 = distance(p2, p3)
        let edge3 = distance(p3, p1)
        
        // Check minimum size
        guard edge1 >= minimumTriangleSize && 
              edge2 >= minimumTriangleSize && 
              edge3 >= minimumTriangleSize else {
            return false
        }
        
        // Check triangle is not too thin
        let s = (edge1 + edge2 + edge3) / 2
        let area = sqrt(s * (s - edge1) * (s - edge2) * (s - edge3))
        let minArea = minimumTriangleSize * minimumTriangleSize / 2
        
        return area >= minArea
    }
    
    private func findNextTriangle(edge: Edge, points: [simd_float3], existingTriangles: [Int32]) -> [Int32]? {
        var bestPoint: Int?
        var minAngle = Float.infinity
        
        let p1 = points[Int(edge.v1)]
        let p2 = points[Int(edge.v2)]
        
        for i in 0..<points.count {
            guard i != Int(edge.v1) && i != Int(edge.v2) else { continue }
            
            let p3 = points[i]
            if isValidTriangle(p1, p2, p3) {
                let angle = calculateAngle(p1, p2, p3)
                if angle < minAngle {
                    minAngle = angle
                    bestPoint = i
                }
            }
        }
        
        if let point = bestPoint {
            return [edge.v1, edge.v2, Int32(point)]
        }
        
        return nil
    }
    
    private func generateNormals(vertices: [SCNVector3], indices: [Int32]) -> SCNGeometrySource? {
        var normals = [SCNVector3](repeating: SCNVector3Zero, count: vertices.count)
        
        // Calculate normals for each triangle and accumulate
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            let v1 = vertices[i1]
            let v2 = vertices[i2]
            let v3 = vertices[i3]
            
            let normal = calculateNormal(v1, v2, v3)
            
            normals[i1] = SCNVector3(normals[i1].x + normal.x,
                                   normals[i1].y + normal.y,
                                   normals[i1].z + normal.z)
            normals[i2] = SCNVector3(normals[i2].x + normal.x,
                                   normals[i2].y + normal.y,
                                   normals[i2].z + normal.z)
            normals[i3] = SCNVector3(normals[i3].x + normal.x,
                                   normals[i3].y + normal.y,
                                   normals[i3].z + normal.z)
        }
        
        // Normalize all normals
        normals = normals.map { normalize($0) }
        
        return SCNGeometrySource(normals: normals)
    }
    
    private func calculateNormal(_ v1: SCNVector3, _ v2: SCNVector3, _ v3: SCNVector3) -> SCNVector3 {
        let edge1 = SCNVector3(v2.x - v1.x, v2.y - v1.y, v2.z - v1.z)
        let edge2 = SCNVector3(v3.x - v1.x, v3.y - v1.y, v3.z - v1.z)
        
        let normal = SCNVector3(
            edge1.y * edge2.z - edge1.z * edge2.y,
            edge1.z * edge2.x - edge1.x * edge2.z,
            edge1.x * edge2.y - edge1.y * edge2.x
        )
        
        return normalize(normal)
    }
    
    private func normalize(_ v: SCNVector3) -> SCNVector3 {
        let length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        guard length > 0 else { return v }
        return SCNVector3(v.x / length, v.y / length, v.z / length)
    }
}

// Helper structs and methods
private struct Edge: Hashable {
    let v1: Int32
    let v2: Int32
    
    init(_ v1: Int32, _ v2: Int32) {
        // Always store vertices in sorted order for proper hash/equality
        if v1 < v2 {
            self.v1 = v1
            self.v2 = v2
        } else {
            self.v1 = v2
            self.v2 = v1
        }
    }
}

private func getTriangleEdges(_ triangle: [Int32]) -> Set<Edge> {
    guard triangle.count >= 3 else { return [] }
    return [
        Edge(triangle[0], triangle[1]),
        Edge(triangle[1], triangle[2]),
        Edge(triangle[2], triangle[0])
    ]
}

private func calculateAngle(_ p1: simd_float3, _ p2: simd_float3, _ p3: simd_float3) -> Float {
    let v1 = normalize(p2 - p1)
    let v2 = normalize(p3 - p1)
    return acos(dot(v1, v2))
}