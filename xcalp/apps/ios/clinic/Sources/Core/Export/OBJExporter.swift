import Foundation
import Metal
import MetalKit

public class OBJExporter {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    
    public init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    public func export(_ scan: ProcessedScan, to url: URL) async throws {
        // Create OBJ file content
        var objContent = """
        # Exported from XCalp Scanning App
        # Vertices: \(scan.mesh.vertices.count)
        # Created: \(Date())
        
        mtllib \(scan.id.uuidString).mtl
        
        """
        
        // Add vertices
        for vertex in scan.mesh.vertices {
            objContent += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }
        
        // Add texture coordinates if available
        if let uvs = scan.mesh.textureCoordinates {
            for uv in uvs {
                objContent += "vt \(uv.x) \(uv.y)\n"
            }
        }
        
        // Add normals
        for normal in scan.mesh.normals {
            objContent += "vn \(normal.x) \(normal.y) \(normal.z)\n"
        }
        
        // Add object name
        objContent += "\no \(scan.id.uuidString)\n"
        objContent += "g default\n"
        
        // Add material reference
        objContent += "usemtl material0\n"
        
        // Add faces
        // OBJ indices are 1-based
        for i in stride(from: 0, to: scan.mesh.indices.count, by: 3) {
            let idx1 = scan.mesh.indices[i] + 1
            let idx2 = scan.mesh.indices[i + 1] + 1
            let idx3 = scan.mesh.indices[i + 2] + 1
            
            if scan.mesh.textureCoordinates != nil {
                objContent += "f \(idx1)/\(idx1)/\(idx1) \(idx2)/\(idx2)/\(idx2) \(idx3)/\(idx3)/\(idx3)\n"
            } else {
                objContent += "f \(idx1)//\(idx1) \(idx2)//\(idx2) \(idx3)//\(idx3)\n"
            }
        }
        
        // Write OBJ file
        try objContent.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        
        // Create and write MTL file
        try await createMTLFile(
            for: scan,
            baseURL: url.deletingLastPathComponent()
        )
        
        // Export textures
        try await exportTextures(
            scan.textures,
            baseURL: url.deletingLastPathComponent(),
            prefix: scan.id.uuidString
        )
    }
    
    private func createMTLFile(
        for scan: ProcessedScan,
        baseURL: URL
    ) async throws {
        let mtlContent = """
        # Material file for \(scan.id.uuidString).obj
        
        newmtl material0
        Ns 32
        Ka 1.000000 1.000000 1.000000
        Kd 0.800000 0.800000 0.800000
        Ks 0.500000 0.500000 0.500000
        Ke 0.000000 0.000000 0.000000
        Ni 1.450000
        d 1.000000
        illum 2
        map_Kd \(scan.id.uuidString)_diffuse.png
        map_Bump \(scan.id.uuidString)_normal.png
        map_Ks \(scan.id.uuidString)_specular.png
        
        """
        
        let mtlURL = baseURL.appendingPathComponent("\(scan.id.uuidString).mtl")
        try mtlContent.write(
            to: mtlURL,
            atomically: true,
            encoding: .utf8
        )
    }
    
    private func exportTextures(
        _ textures: [ProcessedTexture],
        baseURL: URL,
        prefix: String
    ) async throws {
        for texture in textures {
            let suffix: String
            switch texture.type {
            case .diffuse:
                suffix = "diffuse"
            case .normal:
                suffix = "normal"
            case .occlusion:
                suffix = "specular"
            }
            
            let textureURL = baseURL.appendingPathComponent("\(prefix)_\(suffix).png")
            try await exportTexture(texture.texture, to: textureURL)
        }
    }
    
    private func exportTexture(_ texture: MTLTexture, to url: URL) async throws {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let region = MTLRegionMake2D(0, 0, width, height)
        
        var textureBytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &textureBytes,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )
        
        // Create CGImage from texture bytes
        guard let dataProvider = CGDataProvider(
            data: Data(textureBytes) as CFData
        ),
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw ExportError.textureConversionFailed
        }
        
        // Create PNG data
        guard let imageDestination = CGImageDestinationCreateWithURL(
            url as CFURL,
            kUTTypePNG,
            1,
            nil
        ) else {
            throw ExportError.imageExportFailed
        }
        
        // Set image properties
        let imageProperties = [
            kCGImagePropertyPNGCompressionFactor: 1.0
        ] as CFDictionary
        
        CGImageDestinationAddImage(
            imageDestination,
            cgImage,
            imageProperties
        )
        
        if !CGImageDestinationFinalize(imageDestination) {
            throw ExportError.imageExportFailed
        }
    }
}

enum ExportError: Error {
    case textureConversionFailed
    case imageExportFailed
}