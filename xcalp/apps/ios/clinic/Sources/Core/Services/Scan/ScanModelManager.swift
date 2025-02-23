import Foundation
import SceneKit

actor ScanModelManager {
    private let fileManager: FileManager
    private var currentScanURL: URL?
    
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    func setCurrentScan(_ url: URL) {
        currentScanURL = url
    }
    
    func getCurrentScan() -> URL? {
        return currentScanURL
    }
    
    func validateScanModel(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScanModelError.fileNotFound
        }
        
        // Validate file type
        guard url.pathExtension.lowercased() == "usdz" ||
              url.pathExtension.lowercased() == "obj" ||
              url.pathExtension.lowercased() == "scn" else {
            throw ScanModelError.unsupportedFileType
        }
    }
}

enum ScanModelError: Error {
    case fileNotFound
    case unsupportedFileType
    case invalidModel
}