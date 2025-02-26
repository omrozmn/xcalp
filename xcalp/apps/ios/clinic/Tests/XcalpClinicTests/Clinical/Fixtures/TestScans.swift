import Foundation
import simd
import XCalp

struct TestScans {
    static func generateNormalScan() -> Data {
        let mesh = generateBaseMesh(resolution: 100)
        return encodeMeshData(mesh)
    }
    
    static func generateSparseScan() -> Data {
        let mesh = generateBaseMesh(resolution: 50)
        return encodeMeshData(mesh)
    }
    
    static func generateDenseScan() -> Data {
        let mesh = generateBaseMesh(resolution: 200)
        return encodeMeshData(mesh)
    }
    
    static func generateIrregularScan() -> Data {
        var mesh = generateBaseMesh(resolution: 100)
        // Add irregularities to the mesh
        mesh.vertices = addIrregularities(to: mesh.vertices)
        return encodeMeshData(mesh)
    }
    
    private static func generateBaseMesh(resolution: Int) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Generate grid of vertices
        for y in 0..<resolution {
            for x in 0..<resolution {
                let xPos = Float(x) / Float(resolution - 1) * 2 - 1
                let yPos = Float(y) / Float(resolution - 1) * 2 - 1
                
                // Generate realistic scalp shape
                let zPos = generateScalpHeight(x: xPos, y: yPos)
                
                vertices.append(SIMD3<Float>(xPos, yPos, zPos))
                normals.append(calculateNormal(x: xPos, y: yPos, z: zPos))
                
                // Generate indices for triangles
                if x < resolution - 1 && y < resolution - 1 {
                    let current = UInt32(y * resolution + x)
                    let next = current + 1
                    let below = current + UInt32(resolution)
                    let belowNext = below + 1
                    
                    indices.append(current)
                    indices.append(next)
                    indices.append(below)
                    
                    indices.append(next)
                    indices.append(belowNext)
                    indices.append(below)
                }
            }
        }
        
        return MeshData(vertices: vertices, normals: normals, indices: indices)
    }
    
    private static func generateScalpHeight(x: Float, y: Float) -> Float {
        // Basic scalp shape function
        let base = -sqrt(x * x + y * y) * 0.5
        
        // Add natural variations
        let variation = sin(x * 5) * cos(y * 5) * 0.05
        
        return base + variation
    }
    
    private static func calculateNormal(x: Float, y: Float, z: Float) -> SIMD3<Float> {
        // Calculate surface normal using partial derivatives
        let eps: Float = 0.001
        
        let dzdx = (generateScalpHeight(x: x + eps, y: y) - 
                   generateScalpHeight(x: x - eps, y: y)) / (2 * eps)
        
        let dzdy = (generateScalpHeight(x: x, y: y + eps) - 
                   generateScalpHeight(x: x, y: y - eps)) / (2 * eps)
        
        let normal = normalize(SIMD3<Float>(-dzdx, -dzdy, 1))
        return normal
    }
    
    private static func addIrregularities(to vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        return vertices.map { vertex in
            let noise = Float.random(in: -0.1...0.1)
            return vertex + SIMD3<Float>(0, 0, noise)
        }
    }
    
    private static func encodeMeshData(_ mesh: MeshData) -> Data {
        // Encode mesh in OBJ format
        var objString = ""
        
        // Write vertices
        for vertex in mesh.vertices {
            objString += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }
        
        // Write normals
        for normal in mesh.normals {
            objString += "vn \(normal.x) \(normal.y) \(normal.z)\n"
        }
        
        // Write faces
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.indices[i] + 1
            let v2 = mesh.indices[i + 1] + 1
            let v3 = mesh.indices[i + 2] + 1
            objString += "f \(v1)//\(v1) \(v2)//\(v2) \(v3)//\(v3)\n"
        }
        
        return objString.data(using: .utf8)!
    }
}