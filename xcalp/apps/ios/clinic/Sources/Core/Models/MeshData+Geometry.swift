import Foundation
import simd

extension MeshData {
    /// Calculate surface area of the mesh
    var surfaceArea: Float {
        var area: Float = 0
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let v1 = vertices[Int(indices[i])]
            let v2 = vertices[Int(indices[i + 1])]
            let v3 = vertices[Int(indices[i + 2])]
            
            // Calculate triangle area using cross product
            let edge1 = v2 - v1
            let edge2 = v3 - v1
            area += length(cross(edge1, edge2)) * 0.5
        }
        
        return area
    }
    
    /// Calculate approximate volume of the mesh
    var volume: Float {
        var vol: Float = 0
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let v1 = vertices[Int(indices[i])]
            let v2 = vertices[Int(indices[i + 1])]
            let v3 = vertices[Int(indices[i + 2])]
            
            // Use signed tetrahedron volume formula
            vol += dot(cross(v1, v2), v3) / 6.0
        }
        
        return abs(vol)
    }
    
    /// Update bounding box based on current vertices
    mutating func updateBoundingBox() {
        var box = BoundingBox()
        for vertex in vertices {
            box.union(with: vertex)
        }
        metadata.boundingBox = box
    }
    
    /// Calculate local curvature for each vertex
    func calculateCurvature() -> [Float] {
        var curvatures = [Float](repeating: 0, count: vertices.count)
        var neighborCounts = [Int](repeating: 0, count: vertices.count)
        
        // Build vertex adjacency information
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            // Calculate angle-weighted pseudo-curvature
            let angle1 = calculateAngle(vertices[i1], vertices[i2], vertices[i3])
            let angle2 = calculateAngle(vertices[i2], vertices[i3], vertices[i1])
            let angle3 = calculateAngle(vertices[i3], vertices[i1], vertices[i2])
            
            curvatures[i1] += angle1
            curvatures[i2] += angle2
            curvatures[i3] += angle3
            
            neighborCounts[i1] += 1
            neighborCounts[i2] += 1
            neighborCounts[i3] += 1
        }
        
        // Normalize curvatures
        for i in 0..<curvatures.count {
            if neighborCounts[i] > 0 {
                curvatures[i] = (2.0 * .pi - curvatures[i]) / Float(neighborCounts[i])
            }
        }
        
        return curvatures
    }
    
    /// Check if mesh is manifold (each edge shared by exactly two triangles)
    func isManifold() -> Bool {
        var edgeCounts: [Edge: Int] = [:]
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            let i1 = Int(indices[i])
            let i2 = Int(indices[i + 1])
            let i3 = Int(indices[i + 2])
            
            let edges = [
                Edge(v1: i1, v2: i2),
                Edge(v1: i2, v2: i3),
                Edge(v1: i3, v2: i1)
            ]
            
            for edge in edges {
                edgeCounts[edge, default: 0] += 1
            }
        }
        
        // A manifold mesh has exactly 2 triangles per edge
        return edgeCounts.values.allSatisfy { $0 == 2 }
    }
    
    private func calculateAngle(_ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ v3: SIMD3<Float>) -> Float {
        let e1 = normalize(v2 - v1)
        let e2 = normalize(v3 - v1)
        return acos(dot(e1, e2))
    }
}

private struct Edge: Hashable {
    let v1: Int
    let v2: Int
    
    init(v1: Int, v2: Int) {
        if v1 < v2 {
            self.v1 = v1
            self.v2 = v2
        } else {
            self.v1 = v2
            self.v2 = v1
        }
    }
}