import Accelerate
import ARKit
import MetalKit
final class MeshOptimizer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let defaultLibrary: MTLLibrary
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let defaultLibrary = device.makeDefaultLibrary() else {
            throw MeshOptimizerError.metalInitializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.defaultLibrary = defaultLibrary
    }
    
    func optimizeMesh(_ mesh: ARMeshGeometry) throws -> OptimizedMesh {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "meshOptimization",
            category: "processing"
        )
        
        defer {
            PerformanceMonitor.shared.endMeasuring(
                "meshOptimization",
                signpostID: perfID,
                category: "processing"
            )
        }
        
        // Step 1: Noise removal and smoothing
        let denoisedMesh = try removeNoise(from: mesh)
        let smoothedMesh = try smoothMesh(denoisedMesh)
        
        // Step 2: Topology optimization
        let optimizedMesh = try optimizeTopology(smoothedMesh)
        
        // Step 3: Feature preservation
        let refinedMesh = try preserveFeatures(optimizedMesh)
        
        // Step 4: Final validation
        try validateMeshQuality(refinedMesh)
        
        return refinedMesh
    }
    
    private func removeNoise(from mesh: ARMeshGeometry) throws -> ARMeshGeometry {
        let vertices = mesh.vertices
        let normals = mesh.normals
        var cleanedVertices: [SIMD3<Float>] = []
        var cleanedNormals: [SIMD3<Float>] = []
        
        // Statistical outlier removal
        let stdDevThreshold: Float = 2.0
        let kNeighbors = 8
        
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let neighbors = findKNearestNeighbors(to: vertex, in: vertices, k: kNeighbors)
            
            // Calculate mean distance to neighbors
            let meanDist = neighbors.reduce(0.0) { $0 + length($1 - vertex) } / Float(neighbors.count)
            
            // Calculate standard deviation
            let variance = neighbors.reduce(0.0) { $0 + pow(length($1 - vertex) - meanDist, 2) }
            let stdDev = sqrt(variance / Float(neighbors.count))
            
            // Keep vertex if within threshold
            if meanDist <= stdDevThreshold * stdDev {
                cleanedVertices.append(vertex)
                cleanedNormals.append(normals[i])
            }
        }
        
        return createMeshGeometry(vertices: cleanedVertices, normals: cleanedNormals, faces: mesh.faces)
    }
    
    private func smoothMesh(_ mesh: ARMeshGeometry) throws -> ARMeshGeometry {
        let vertices = mesh.vertices
        let normals = mesh.normals
        var smoothedVertices: [SIMD3<Float>] = Array(repeating: .zero, count: vertices.count)
        var smoothedNormals: [SIMD3<Float>] = Array(repeating: .zero, count: normals.count)
        
        // Laplacian smoothing with feature preservation
        let lambda: Float = 0.5 // Smoothing factor
        let iterations = 3
        
        for _ in 0..<iterations {
            for i in 0..<vertices.count {
                let vertex = vertices[i]
                let normal = normals[i]
                let neighbors = findNeighborVertices(for: i, in: mesh)
                
                if !neighbors.isEmpty {
                    // Calculate centroid of neighbors
                    let centroid = neighbors.reduce(.zero, +) / Float(neighbors.count)
                    
                    // Calculate feature intensity
                    let featureIntensity = calculateFeatureIntensity(vertex: vertex, normal: normal, neighbors: neighbors)
                    
                    // Adaptive smoothing based on feature intensity
                    let adaptiveLambda = lambda * (1.0 - featureIntensity)
                    smoothedVertices[i] = mix(vertex, centroid, t: adaptiveLambda)
                    
                    // Update normal
                    let smoothedNormal = neighbors.map { calculateNormal(vertex, $0) }.reduce(.zero, +)
                    smoothedNormals[i] = normalize(smoothedNormal)
                } else {
                    smoothedVertices[i] = vertex
                    smoothedNormals[i] = normal
                }
            }
        }
        
        return createMeshGeometry(vertices: smoothedVertices, normals: smoothedNormals, faces: mesh.faces)
    }
    
    private func optimizeTopology(_ mesh: ARMeshGeometry) throws -> ARMeshGeometry {
        let vertices = mesh.vertices
        let faces = mesh.faces
        var optimizedFaces: [UInt32] = []
        
        // Edge collapse and face merge optimization
        let edgeLengthThreshold: Float = 0.01 // 1cm
        var processedEdges: Set<Edge> = []
        
        for i in stride(from: 0, to: faces.count, by: 3) {
            let faceIndices = [faces[i], faces[i + 1], faces[i + 2]]
            let faceVertices = faceIndices.map { vertices[Int($0)] }
            
            // Check each edge of the face
            for j in 0..<3 {
                let v1 = faceVertices[j]
                let v2 = faceVertices[(j + 1) % 3]
                let edge = Edge(v1: v1, v2: v2)
                
                if !processedEdges.contains(edge) {
                    processedEdges.insert(edge)
                    
                    // Check if edge should be collapsed
                    if length(v2 - v1) < edgeLengthThreshold {
                        // Collapse edge to midpoint
                        let midpoint = (v1 + v2) / 2
                        optimizedFaces.append(contentsOf: updateFaceIndices(faces: faces, v1: v1, v2: v2, newVertex: midpoint))
                    } else {
                        optimizedFaces.append(contentsOf: faceIndices)
                    }
                }
            }
        }
        
        return createMeshGeometry(vertices: vertices, normals: mesh.normals, faces: optimizedFaces)
    }
    
    private func preserveFeatures(_ mesh: ARMeshGeometry) throws -> OptimizedMesh {
        let vertices = mesh.vertices
        let normals = mesh.normals
        var featureVertices: [SIMD3<Float>] = []
        var featureStrengths: [Float] = []
        
        // Detect and preserve sharp features
        let sharpnessThreshold: Float = 0.7
        
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let normal = normals[i]
            let neighbors = findNeighborVertices(for: i, in: mesh)
            
            // Calculate feature strength using dihedral angles
            let featureStrength = calculateFeatureStrength(
                vertex: vertex,
                normal: normal,
                neighbors: neighbors,
                threshold: sharpnessThreshold
            )
            
            if featureStrength > sharpnessThreshold {
                featureVertices.append(vertex)
                featureStrengths.append(featureStrength)
            }
        }
        
        return OptimizedMesh(
            vertices: vertices,
            normals: normals,
            faces: mesh.faces,
            featureVertices: featureVertices,
            featureStrengths: featureStrengths
        )
    }
    
    private func validateMeshQuality(_ mesh: OptimizedMesh) throws {
        // Validate mesh integrity
        guard mesh.vertices.count >= 3,
              mesh.faces.count >= 3,
              mesh.vertices.count == mesh.normals.count else {
            throw MeshOptimizerError.invalidMeshStructure
        }
        
        // Check for degenerate faces
        for i in stride(from: 0, to: mesh.faces.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.faces[i])]
            let v2 = mesh.vertices[Int(mesh.faces[i + 1])]
            let v3 = mesh.vertices[Int(mesh.faces[i + 2])]
            
            let area = calculateTriangleArea(v1: v1, v2: v2, v3: v3)
            if area < Float.ulpOfOne {
                throw MeshOptimizerError.degenerateFacesDetected
            }
        }
        
        // Validate normal consistency
        for (vertex, normal) in zip(mesh.vertices, mesh.normals) {
            if abs(length(normal) - 1.0) > 0.01 {
                throw MeshOptimizerError.inconsistentNormals
            }
        }
    }
    
    // Helper methods
    private func findNeighborVertices(for index: Int, in mesh: ARMeshGeometry) -> [SIMD3<Float>] {
        var neighbors: [SIMD3<Float>] = []
        let vertices = mesh.vertices
        let faces = mesh.faces
        
        for i in stride(from: 0, to: faces.count, by: 3) {
            let faceIndices = [Int(faces[i]), Int(faces[i + 1]), Int(faces[i + 2])]
            if faceIndices.contains(index) {
                // Add other vertices from the face
                for j in faceIndices where j != index {
                    neighbors.append(vertices[j])
                }
            }
        }
        
        return neighbors
    }
    
    private func calculateFeatureIntensity(vertex: SIMD3<Float>, normal: SIMD3<Float>, neighbors: [SIMD3<Float>]) -> Float {
        guard !neighbors.isEmpty else { return 0.0 }
        
        // Calculate variation in normals
        let neighborNormals = neighbors.map { calculateNormal(vertex, $0) }
        let averageNormal = normalize(neighborNormals.reduce(.zero, +))
        
        // Higher intensity for larger deviations from average normal
        return 1.0 - abs(dot(normal, averageNormal))
    }
    
    private func calculateFeatureStrength(
        vertex: SIMD3<Float>,
        normal: SIMD3<Float>,
        neighbors: [SIMD3<Float>],
        threshold: Float
    ) -> Float {
        guard !neighbors.isEmpty else { return 0.0 }
        
        var strength: Float = 0.0
        var count: Int = 0
        
        for neighbor in neighbors {
            let edge = normalize(neighbor - vertex)
            let angle = acos(abs(dot(normal, edge)))
            
            if angle > threshold {
                strength += angle
                count += 1
            }
        }
        
        return !isEmpty ? strength / Float(count) : 0.0
    }
    
    private func calculateNormal(_ v1: SIMD3<Float>, _ v2: SIMD3<Float>) -> SIMD3<Float> {
        normalize(cross(v1, v2))
    }
    
    private func calculateTriangleArea(v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>) -> Float {
        let cross = cross(v2 - v1, v3 - v1)
        return length(cross) / 2
    }
    
    private func createMeshGeometry(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        faces: [UInt32]
    ) -> ARMeshGeometry {
        // Create vertex and normal buffers
        let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        
        let normalBuffer = device.makeBuffer(
            bytes: normals,
            length: normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        
        let faceBuffer = device.makeBuffer(
            bytes: faces,
            length: faces.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )
        
        // Create geometry source descriptors
        let vertexSource = ARGeometrySource(
            buffer: vertexBuffer!,
            vertexCount: vertices.count,
            format: .float3,
            semantic: .vertex,
            baseOffset: 0,
            stride: MemoryLayout<SIMD3<Float>>.stride
        )
        
        let normalSource = ARGeometrySource(
            buffer: normalBuffer!,
            vertexCount: normals.count,
            format: .float3,
            semantic: .normal,
            baseOffset: 0,
            stride: MemoryLayout<SIMD3<Float>>.stride
        )
        
        let faceElement = ARGeometryElement(
            buffer: faceBuffer!,
            primitiveType: .triangle,
            elementCount: faces.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        return ARMeshGeometry(
            vertices: vertexSource,
            normals: normalSource,
            faces: faceElement
        )
    }
}

// Supporting types
struct OptimizedMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let faces: [UInt32]
    let featureVertices: [SIMD3<Float>]
    let featureStrengths: [Float]
}

struct Edge: Hashable {
    let v1: SIMD3<Float>
    let v2: SIMD3<Float>
    
    func hash(into hasher: inout Hasher) {
        // Order-independent hashing
        hasher.combine(min(v1.x, v2.x))
        hasher.combine(max(v1.x, v2.x))
        hasher.combine(min(v1.y, v2.y))
        hasher.combine(max(v1.y, v2.y))
        hasher.combine(min(v1.z, v2.z))
        hasher.combine(max(v1.z, v2.z))
    }
    
    static func == (lhs: Edge, rhs: Edge) -> Bool {
        (simd_equal(lhs.v1, rhs.v1) && simd_equal(lhs.v2, rhs.v2)) ||
               (simd_equal(lhs.v1, rhs.v2) && simd_equal(lhs.v2, rhs.v1))
    }
}

enum MeshOptimizerError: Error {
    case metalInitializationFailed
    case invalidMeshStructure
    case degenerateFacesDetected
    case inconsistentNormals
    case optimizationFailed
}
