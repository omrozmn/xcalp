import Foundation
import CoreData

class OfflineCapabilitiesManager {
    private let persistenceController: PersistenceController
    private let syncManager: CrossPlatformSyncManager
    private var pendingChanges: [PendingChange] = []
    
    init(persistenceController: PersistenceController, syncManager: CrossPlatformSyncManager) {
        self.persistenceController = persistenceController
        self.syncManager = syncManager
    }
    
    func saveForOffline(_ data: ScanData) async throws {
        // Save to local storage
        try await persistenceController.save(data)
        
        // Track pending change
        pendingChanges.append(PendingChange(
            id: data.id,
            type: .create,
            timestamp: Date()
        ))
    }
    
    func updateOffline(_ data: ScanData) async throws {
        try await persistenceController.update(data)
        pendingChanges.append(PendingChange(
            id: data.id,
            type: .update,
            timestamp: Date()
        ))
    }
    
    func syncWhenOnline() async throws {
        guard !pendingChanges.isEmpty else { return }
        
        // Sort changes by timestamp
        let sortedChanges = pendingChanges.sorted { $0.timestamp < $1.timestamp }
        
        for change in sortedChanges {
            if let data = try await persistenceController.fetch(id: change.id) {
                // Attempt to sync
                do {
                    let result = try await syncManager.sync(data: data)
                    if result.success {
                        pendingChanges.removeAll { $0.id == change.id }
                    }
                } catch {
                    // Log failure but continue with other changes
                    logger.error("Failed to sync change: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getPendingChangesCount() -> Int {
        return pendingChanges.count
    }
}

private struct PendingChange: Codable {
    let id: UUID
    let type: ChangeType
    let timestamp: Date
}

private enum ChangeType: String, Codable {
    case create
    case update
    case delete
}

private extension OfflineCapabilitiesManager {
    func validateStorageSpace() throws {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let values = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let availableSpace = values.volumeAvailableCapacity,
              availableSpace > 500_000_000 else { // 500MB minimum
            throw OfflineStorageError.insufficientSpace
        }
    }
}

enum OfflineStorageError: Error {
    case insufficientSpace
    case dataCorrupted
    case syncFailed(Error)
}