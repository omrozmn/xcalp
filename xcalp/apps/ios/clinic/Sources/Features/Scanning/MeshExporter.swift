import ARKit
import Foundation
import ModelIO
import SceneKit

public struct MeshExporter {
    public enum ExportError: Error {
        case invalidMeshData
        case exportFailed(String)
        case unsupportedFormat
    }
    
    public func exportMesh(_ mesh: ARMeshAnchor, to format: ScanHistoryManager.ScanVersion.ExportFormat) async throws -> URL {
        let vertices = mesh.geometry.vertices
        let normals = mesh.geometry.normals
        let indices = mesh.geometry.faces
        
        switch format {
        case .obj:
            return try await exportToOBJ(vertices: vertices, normals: normals, indices: indices)
        case .stl:
            return try await exportToSTL(vertices: vertices, normals: normals, indices: indices)
        case .ply:
            return try await exportToPLY(vertices: vertices, normals: normals, indices: indices)
        case .usdz:
            return try await exportToUSDZ(vertices: vertices, normals: normals, indices: indices)
        }
    }
    
    private func exportToOBJ(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".obj")
        
        var objContent = "# Exported from Xcalp Clinic\n"
        
        // Write vertices
        for vertex in vertices {
            objContent += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }
        
        // Write normals
        for normal in normals {
            objContent += "vn \(normal.x) \(normal.y) \(normal.z)\n"
        }
        
        // Write faces (convert from zero-based to one-based indexing)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let idx1 = indices[i] + 1
            let idx2 = indices[i + 1] + 1
            let idx3 = indices[i + 2] + 1
            objContent += "f \(idx1)//\(idx1) \(idx2)//\(idx2) \(idx3)//\(idx3)\n"
        }
        
        try objContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    private func exportToSTL(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".stl")
        var stlContent = Data()
        
        // STL Header (80 bytes)
        let header = "Xcalp Clinic Export".padding(toLength: 80, withPad: " ", startingAt: 0)
        stlContent.append(header.data(using: .ascii)!)
        
        // Number of triangles (4 bytes)
        let triangleCount = UInt32(indices.count / 3)
        stlContent.append(triangleCount.data)
        
        // Write triangles
        for i in stride(from: 0, to: indices.count, by: 3) {
            let normal = normals[Int(indices[i])]
            
            // Normal vector (12 bytes)
            stlContent.append(normal.x.data)
            stlContent.append(normal.y.data)
            stlContent.append(normal.z.data)
            
            // Vertices (36 bytes)
            for j in 0...2 {
                let vertex = vertices[Int(indices[i + j])]
                stlContent.append(vertex.x.data)
                stlContent.append(vertex.y.data)
                stlContent.append(vertex.z.data)
            }
            
            // Attribute byte count (2 bytes)
            stlContent.append(UInt16(0).data)
        }
        
        try stlContent.write(to: tempURL)
        return tempURL
    }
    
    private func exportToPLY(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ply")
        var plyContent = """
        ply
        format ascii 1.0
        comment Exported from Xcalp Clinic
        element vertex \(vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(indices.count / 3)
        property list uchar int vertex_indices
        end_header
        
        """
        
        // Write vertices and normals
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let normal = normals[i]
            plyContent += "\(vertex.x) \(vertex.y) \(vertex.z) \(normal.x) \(normal.y) \(normal.z)\n"
        }
        
        // Write faces
        for i in stride(from: 0, to: indices.count, by: 3) {
            plyContent += "3 \(indices[i]) \(indices[i + 1]) \(indices[i + 2])\n"
        }
        
        try plyContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    private func exportToUSDZ(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) async throws -> URL {
        // Create a temporary SCNGeometry
        let vertexSource = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
        
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(data: indexData,
                                       primitiveType: .triangles,
                                       primitiveCount: indices.count / 3,
                                       bytesPerIndex: MemoryLayout<UInt32>.size)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        
        // Create a node with the geometry
        let node = SCNNode(geometry: geometry)
        
        // Create a scene
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        
        // Export to USDZ
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
        
        try await scene.write(to: tempURL, options: nil, delegate: nil, progressHandler: nil)
        return tempURL
    }
}

// Extensions to help with binary data conversion
extension Float {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<Float>.size)
    }
}

extension UInt16 {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
