import Foundation
import UniformTypeIdentifiers

class ExportManager {
    enum ExportError: Error {
        case invalidData
        case saveFailed
        case exportFailed
    }
    
    func saveToFiles(_ data: Data, filename: String) throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            throw ExportError.saveFailed
        }
    }
    
    func generateExportURL(for data: Data, format: ModelExportFormat) throws -> URL {
        let filename: String
        switch format {
        case .usdz:
            filename = "scan_\(Date().timeIntervalSince1970).usdz"
        case .obj:
            filename = "scan_\(Date().timeIntervalSince1970).obj"
        case .ply:
            filename = "scan_\(Date().timeIntervalSince1970).ply"
        }
        
        return try saveToFiles(data, filename: filename)
    }
    
    func getContentType(for format: ModelExportFormat) -> UTType {
        switch format {
        case .usdz:
            return UTType.usdz
        case .obj:
            return UTType.obj
        case .ply:
            return UTType.ply
        }
    }
}

private extension UTType {
    static let usdz = UTType("com.pixar.universal-scene-description-mobile")!
    static let obj = UTType("public.geometry-definition-format")!
    static let ply = UTType("public.polygon-file-format")!
}