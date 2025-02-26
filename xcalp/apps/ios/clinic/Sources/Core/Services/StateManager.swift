import Foundation
import CryptoKit
import CoreData

public actor StateManager {
    public static let shared = StateManager()
    
    private let secureStorage: SecureStorageService
    private let encryptionService: EncryptionService
    private let hipaaLogger: HIPAALogger
    private let stateDirectory: URL
    
    private init(
        secureStorage: SecureStorageService = .shared,
        encryptionService: EncryptionService = .shared,
        hipaaLogger: HIPAALogger = .shared
    ) {
        self.secureStorage = secureStorage
        self.encryptionService = encryptionService
        self.hipaaLogger = hipaaLogger
        
        // Setup state directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.stateDirectory = appSupport.appendingPathComponent("AppState", isDirectory: true)
        
        setupStateDirectory()
    }
    
    public func saveState(_ sessionId: String) async throws {
        // Create state blocks
        let dataBlocks = try await createDataBlocks()
        
        // Generate checksums
        let checksums = generateChecksums(for: dataBlocks)
        
        // Get secure storage state
        let secureData = try await secureStorage.performSecureOperation {
            try await exportSecureStorageState()
        }
        
        // Get session state
        let sessionData = try await exportSessionState()
        
        // Create app state
        let state = try await createAppState(
            dataBlocks: dataBlocks,
            checksums: checksums,
            secureData: secureData,
            sessionData: sessionData
        )
        
        // Save state
        try await saveState(state, for: sessionId)
        
        // Log state save
        await hipaaLogger.log(
            event: .stateSaved,
            details: [
                "sessionId": sessionId,
                "timestamp": Date(),
                "version": state.version
            ]
        )
    }
    
    public func loadState(_ sessionId: String) async throws -> AppState {
        // Get state file
        let stateFile = try getStateFile(for: sessionId)
        
        // Load encrypted state
        let encryptedData = try Data(contentsOf: stateFile)
        
        // Decrypt state
        let stateData = try await secureStorage.performSecureOperation {
            try encryptionService.decrypt(encryptedData)
        }
        
        // Decode state
        let decoder = JSONDecoder()
        let state = try decoder.decode(AppState.self, from: stateData)
        
        // Log state load
        await hipaaLogger.log(
            event: .stateLoaded,
            details: [
                "sessionId": sessionId,
                "timestamp": Date(),
                "version": state.version
            ]
        )
        
        return state
    }
    
    public func clearState(_ sessionId: String) async throws {
        let stateFile = try getStateFile(for: sessionId)
        try FileManager.default.removeItem(at: stateFile)
        
        await hipaaLogger.log(
            event: .stateCleared,
            details: [
                "sessionId": sessionId,
                "timestamp": Date()
            ]
        )
    }
    
    private func createDataBlocks() async throws -> [StateIntegrityVerifier.DataBlock] {
        var blocks: [StateIntegrityVerifier.DataBlock] = []
        var previousHash: SHA256.Digest = SHA256.hash(data: Data())
        
        // Get managed object contexts
        let context = secureStorage.mainContext
        
        // Create blocks for each entity type
        for entityName in try context.persistentStoreCoordinator?.managedObjectModel.entities ?? [] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName.name!)
            let objects = try context.fetch(request)
            
            // Create block for entity
            let blockData = try NSKeyedArchiver.archivedData(
                withRootObject: objects,
                requiringSecureCoding: true
            )
            
            let hash = SHA256.hash(data: blockData)
            
            let block = StateIntegrityVerifier.DataBlock(
                sequence: blocks.count,
                previousHash: previousHash,
                hash: hash,
                data: blockData
            )
            
            blocks.append(block)
            previousHash = hash
        }
        
        return blocks
    }
    
    private func generateChecksums(
        for blocks: [StateIntegrityVerifier.DataBlock]
    ) -> [StateIntegrityVerifier.Checksum] {
        return blocks.map { block in
            StateIntegrityVerifier.Checksum(
                blockId: UUID(),
                hash: block.hash,
                timestamp: Date()
            )
        }
    }
    
    private func createAppState(
        dataBlocks: [StateIntegrityVerifier.DataBlock],
        checksums: [StateIntegrityVerifier.Checksum],
        secureData: Data,
        sessionData: Data
    ) async throws -> AppState {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1.0"
        let timestamp = Date()
        
        // Combine all data for signature
        var signatureData = Data()
        signatureData.append(version.data(using: .utf8)!)
        signatureData.append(withUnsafeBytes(of: timestamp.timeIntervalSince1970) { Data($0) })
        for block in dataBlocks {
            signatureData.append(block.data)
        }
        
        let signature = SHA256.hash(data: signatureData)
        
        return AppState(
            version: version,
            timestamp: timestamp,
            signature: signature,
            data: signatureData,
            dataBlocks: dataBlocks,
            checksums: checksums,
            entities: try getEntityObjectIDs(),
            secureData: secureData,
            sessionData: sessionData
        )
    }
    
    private func saveState(_ state: AppState, for sessionId: String) async throws {
        let encoder = JSONEncoder()
        let stateData = try encoder.encode(state)
        
        // Encrypt state
        let encryptedData = try await secureStorage.performSecureOperation {
            try encryptionService.encrypt(stateData)
        }
        
        // Save to file
        let stateFile = try getStateFile(for: sessionId)
        try encryptedData.write(to: stateFile)
    }
    
    private func exportSecureStorageState() async throws -> Data {
        // Implementation for exporting secure storage state
        return Data()
    }
    
    private func exportSessionState() async throws -> Data {
        // Implementation for exporting session state
        return Data()
    }
    
    private func getEntityObjectIDs() throws -> [NSManagedObjectID] {
        let context = secureStorage.mainContext
        var objectIDs: [NSManagedObjectID] = []
        
        for entityName in try context.persistentStoreCoordinator?.managedObjectModel.entities ?? [] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName.name!)
            let objects = try context.fetch(request)
            objectIDs.append(contentsOf: objects.map { $0.objectID })
        }
        
        return objectIDs
    }
    
    private func getStateFile(for sessionId: String) throws -> URL {
        return stateDirectory.appendingPathComponent("\(sessionId).state")
    }
    
    private func setupStateDirectory() {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: stateDirectory.path) {
            try? fileManager.createDirectory(
                at: stateDirectory,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )
        }
        
        // Set file protection
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? stateDirectory.setResourceValues(resourceValues)
    }
}

extension HIPAALogger.Event {
    static let stateSaved = HIPAALogger.Event(name: "state_saved")
    static let stateLoaded = HIPAALogger.Event(name: "state_loaded")
    static let stateCleared = HIPAALogger.Event(name: "state_cleared")
}