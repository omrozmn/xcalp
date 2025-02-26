import Foundation
import SceneKit
import CoreData
import RxSwift

class ScanDataManager {
    static let shared = ScanDataManager()
    private let fileManager = FileManager.default
    
    private var scansDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Scans", isDirectory: true)
    }
    
    init() {
        try? fileManager.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
    }
    
    func saveScan(mesh: SCNGeometry, patientId: String, date: Date = Date()) -> Single<String> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(ScanError.internalError))
                return Disposables.create()
            }
            
            let scanId = UUID().uuidString
            let scanFolder = self.scansDirectory.appendingPathComponent(scanId)
            
            do {
                // Create scan folder
                try self.fileManager.createDirectory(at: scanFolder, withIntermediateDirectories: true)
                
                // Save scan metadata
                let metadata = ScanMetadata(
                    id: scanId,
                    patientId: patientId,
                    date: date,
                    version: "1.0"
                )
                
                let metadataURL = scanFolder.appendingPathComponent("metadata.json")
                let metadataData = try JSONEncoder().encode(metadata)
                try metadataData.write(to: metadataURL)
                
                // Save mesh geometry
                let meshURL = scanFolder.appendingPathComponent("scan.scn")
                let scene = SCNScene()
                let node = SCNNode(geometry: mesh)
                scene.rootNode.addChildNode(node)
                scene.write(to: meshURL, options: nil, delegate: nil)
                
                single(.success(scanId))
            } catch {
                single(.failure(ScanError.saveFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func loadScan(id: String) -> Single<(SCNGeometry, ScanMetadata)> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(ScanError.internalError))
                return Disposables.create()
            }
            
            let scanFolder = self.scansDirectory.appendingPathComponent(id)
            
            do {
                // Load metadata
                let metadataURL = scanFolder.appendingPathComponent("metadata.json")
                let metadataData = try Data(contentsOf: metadataURL)
                let metadata = try JSONDecoder().decode(ScanMetadata.self, from: metadataData)
                
                // Load mesh
                let meshURL = scanFolder.appendingPathComponent("scan.scn")
                guard let scene = try SCNScene(url: meshURL, options: nil),
                      let mesh = scene.rootNode.childNodes.first?.geometry else {
                    throw ScanError.invalidScanData
                }
                
                single(.success((mesh, metadata)))
            } catch {
                single(.failure(ScanError.loadFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func deleteScan(id: String) -> Single<Void> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(ScanError.internalError))
                return Disposables.create()
            }
            
            let scanFolder = self.scansDirectory.appendingPathComponent(id)
            
            do {
                try self.fileManager.removeItem(at: scanFolder)
                single(.success(()))
            } catch {
                single(.failure(ScanError.deleteFailed(error)))
            }
            
            return Disposables.create()
        }
    }
    
    func listScansForPatient(id: String) -> Single<[ScanMetadata]> {
        return Single.create { [weak self] single in
            guard let self = self else {
                single(.failure(ScanError.internalError))
                return Disposables.create()
            }
            
            do {
                let contents = try self.fileManager.contentsOfDirectory(
                    at: self.scansDirectory,
                    includingPropertiesForKeys: nil
                )
                
                var scans: [ScanMetadata] = []
                for scanFolder in contents {
                    let metadataURL = scanFolder.appendingPathComponent("metadata.json")
                    if let metadataData = try? Data(contentsOf: metadataURL),
                       let metadata = try? JSONDecoder().decode(ScanMetadata.self, from: metadataData),
                       metadata.patientId == id {
                        scans.append(metadata)
                    }
                }
                
                single(.success(scans.sorted { $0.date > $1.date }))
            } catch {
                single(.failure(ScanError.listFailed(error)))
            }
            
            return Disposables.create()
        }
    }
}

// MARK: - Supporting Types

struct ScanMetadata: Codable {
    let id: String
    let patientId: String
    let date: Date
    let version: String
}

enum ScanError: Error {
    case internalError
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case listFailed(Error)
    case invalidScanData
}