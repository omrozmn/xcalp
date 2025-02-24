import Foundation
import ModelIO
import simd

class IsoSurfaceExtractor {
    private let resolution: Int = 64
    private let isoValue: Float = 0.0
    
    func extractIsoSurface(from octree: OctreeNode) -> MDLMesh {
        // Create sampling grid
        let boundingBox = octree.boundingBox
        let cellSize = (boundingBox.max - boundingBox.min) / Float(resolution)
        
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // March through the grid
        for i in 0..<resolution {
            for j in 0..<resolution {
                for k in 0..<resolution {
                    let position = boundingBox.min + SIMD3<Float>(
                        Float(i) * cellSize.x,
                        Float(j) * cellSize.y,
                        Float(k) * cellSize.z
                    )
                    
                    // Extract cube vertices
                    processCube(at: position,
                              size: cellSize,
                              octree: octree,
                              vertices: &vertices,
                              indices: &indices)
                }
            }
        }
        
        // Create mesh from vertices and indices
        return createMesh(vertices: vertices, indices: indices)
    }
    
    private func processCube(at position: SIMD3<Float>,
                           size: SIMD3<Float>,
                           octree: OctreeNode,
                           vertices: inout [SIMD3<Float>],
                           indices: inout [UInt32]) {
        // Sample implicit function at cube corners
        var cornerValues: [Float] = []
        var cornerPositions: [SIMD3<Float>] = []
        
        for i in 0...1 {
            for j in 0...1 {
                for k in 0...1 {
                    let cornerPos = position + SIMD3<Float>(
                        Float(i) * size.x,
                        Float(j) * size.y,
                        Float(k) * size.z
                    )
                    cornerPositions.append(cornerPos)
                    cornerValues.append(octree.evaluateImplicitFunction(at: cornerPos))
                }
            }
        }
        
        // Determine cube configuration
        var cubeIndex = 0
        for i in 0..<8 {
            if cornerValues[i] < isoValue {
                cubeIndex |= (1 << i)
            }
        }
        
        // Get triangulation for this configuration
        let triangulation = MarchingCubesTables.triangulation[cubeIndex]
        
        // Generate triangles
        var i = 0
        while triangulation[i] != -1 {
            let edge = triangulation[i]
            let v1 = MarchingCubesTables.edgeVertices[edge].0
            let v2 = MarchingCubesTables.edgeVertices[edge].1
            
            // Interpolate vertex position
            let t = (isoValue - cornerValues[v1]) / (cornerValues[v2] - cornerValues[v1])
            let vertex = mix(cornerPositions[v1], cornerPositions[v2], t: t)
            
            vertices.append(vertex)
            indices.append(UInt32(vertices.count - 1))
            
            i += 1
        }
    }
    
    private func createMesh(vertices: [SIMD3<Float>], indices: [UInt32]) -> MDLMesh {
        let allocator = MDLMeshBufferDataAllocator()
        
        // Create vertex buffer
        let vertexBuffer = allocator.newBuffer(vertices.count * MemoryLayout<SIMD3<Float>>.stride,
                                             type: .vertex)
        let vertexMap = vertexBuffer.map()
        vertexMap.bytes.assumingMemoryBound(to: SIMD3<Float>.self)
            .assign(from: vertices, count: vertices.count)
        
        // Create index buffer
        let indexBuffer = allocator.newBuffer(indices.count * MemoryLayout<UInt32>.stride,
                                            type: .index)
        let indexMap = indexBuffer.map()
        indexMap.bytes.assumingMemoryBound(to: UInt32.self)
            .assign(from: indices, count: indices.count)
        
        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                          format: .float3,
                                                          offset: 0,
                                                          bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        
        // Create submesh
        let submesh = MDLSubmesh(indexBuffer: indexBuffer,
                               indexCount: indices.count,
                               indexType: .uInt32,
                               geometryType: .triangles,
                               material: nil)
        
        // Create mesh
        return MDLMesh(vertexBuffer: vertexBuffer,
                      vertexCount: vertices.count,
                      descriptor: vertexDescriptor,
                      submeshes: [submesh])
    }
    
    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a * (1 - t) + b * t
    }
}