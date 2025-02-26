import Foundation
import simd

final class TestMeshGenerator {
    enum MeshType {
        case sphere
        case cube
        case cylinder
        case noise
        case corrupted
    }
    
    static func generateTestMesh(_ type: MeshType, resolution: Int = 32) -> MeshData {
        switch type {
        case .sphere:
            return generateSphere(resolution: resolution)
        case .cube:
            return generateCube(resolution: resolution)
        case .cylinder:
            return generateCylinder(resolution: resolution)
        case .noise:
            return generateNoiseData(resolution: resolution)
        case .corrupted:
            return generateCorruptedMesh(resolution: resolution)
        }
    }
    
    private static func generateSphere(resolution: Int) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Generate sphere vertices using spherical coordinates
        for i in 0...resolution {
            let phi = Float.pi * Float(i) / Float(resolution)
            for j in 0...resolution {
                let theta = 2 * Float.pi * Float(j) / Float(resolution)
                
                let x = sin(phi) * cos(theta)
                let y = sin(phi) * sin(theta)
                let z = cos(phi)
                
                let vertex = SIMD3<Float>(x, y, z)
                vertices.append(vertex)
                normals.append(normalize(vertex))
                confidence.append(1.0)
                
                // Generate quad indices
                if i < resolution && j < resolution {
                    let current = UInt32(i * (resolution + 1) + j)
                    let next = current + 1
                    let bottom = current + UInt32(resolution + 1)
                    let bottomNext = bottom + 1
                    
                    // First triangle
                    indices.append(current)
                    indices.append(next)
                    indices.append(bottom)
                    
                    // Second triangle
                    indices.append(next)
                    indices.append(bottomNext)
                    indices.append(bottom)
                }
            }
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .reconstruction)
        )
    }
    
    private static func generateCube(resolution: Int) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Generate vertices for each face
        let faces = [
            (SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 0, 0)),  // Top
            (SIMD3<Float>(0, -1, 0), SIMD3<Float>(1, 0, 0)), // Bottom
            (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)),  // Right
            (SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0)), // Left
            (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0)),  // Front
            (SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0))  // Back
        ]
        
        for (normal, tangent) in faces {
            let bitangent = cross(normal, tangent)
            
            for i in 0...resolution {
                let u = Float(i) / Float(resolution) * 2 - 1
                for j in 0...resolution {
                    let v = Float(j) / Float(resolution) * 2 - 1
                    
                    let vertex = normal + u * tangent + v * bitangent
                    vertices.append(normalize(vertex))
                    normals.append(normal)
                    confidence.append(1.0)
                    
                    if i < resolution && j < resolution {
                        let current = UInt32(vertices.count - 1)
                        let next = current + 1
                        let bottom = current + UInt32(resolution + 1)
                        let bottomNext = bottom + 1
                        
                        indices.append(current)
                        indices.append(next)
                        indices.append(bottom)
                        
                        indices.append(next)
                        indices.append(bottomNext)
                        indices.append(bottom)
                    }
                }
            }
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .reconstruction)
        )
    }
    
    private static func generateCylinder(resolution: Int) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Generate cylinder vertices
        for i in 0...resolution {
            let angle = 2 * Float.pi * Float(i) / Float(resolution)
            for h in 0...resolution {
                let height = Float(h) / Float(resolution) * 2 - 1
                
                let x = cos(angle)
                let y = height
                let z = sin(angle)
                
                let vertex = SIMD3<Float>(x, y, z)
                let normal = normalize(SIMD3<Float>(x, 0, z))
                
                vertices.append(vertex)
                normals.append(normal)
                confidence.append(1.0)
                
                if i < resolution && h < resolution {
                    let current = UInt32(i * (resolution + 1) + h)
                    let next = current + 1
                    let bottom = UInt32((i + 1) % (resolution + 1)) * UInt32(resolution + 1) + UInt32(h)
                    let bottomNext = bottom + 1
                    
                    indices.append(current)
                    indices.append(next)
                    indices.append(bottom)
                    
                    indices.append(next)
                    indices.append(bottomNext)
                    indices.append(bottom)
                }
            }
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .reconstruction)
        )
    }
    
    private static func generateNoiseData(resolution: Int) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        // Generate noisy point cloud
        for _ in 0..<(resolution * resolution) {
            let vertex = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            vertices.append(vertex)
            
            let normal = normalize(SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            ))
            normals.append(normal)
            confidence.append(Float.random(in: 0...1))
        }
        
        // Generate random triangles
        for i in stride(from: 0, to: vertices.count - 2, by: 3) {
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .reconstruction)
        )
    }
    
    private static func generateCorruptedMesh(resolution: Int) -> MeshData {
        var mesh = generateSphere(resolution: resolution)
        
        // Introduce corruption
        for i in 0..<(mesh.vertices.count / 4) {
            // Corrupt vertices
            mesh.vertices[i] = SIMD3<Float>(
                .infinity,
                .nan,
                -.infinity
            )
            
            // Corrupt normals
            mesh.normals[i] = .zero
            
            // Corrupt confidence
            mesh.confidence[i] = -1.0
        }
        
        // Corrupt indices
        for i in 0..<(mesh.indices.count / 4) {
            mesh.indices[i] = UInt32.max
        }
        
        return mesh
    }
}