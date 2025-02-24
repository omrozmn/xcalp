import CloudKit
import Combine

public class CloudSyncManager {
    private let container: CKContainer
    private let database: CKDatabase
    private var subscriptions = Set<AnyCancellable>()
    
    public enum SyncError: Error {
        case uploadFailed(Error)
        case downloadFailed(Error)
        case recordNotFound
        case invalidRecord
    }
    
    public init(containerId: String = "iCloud.com.xcalp.clinic") {
        self.container = CKContainer(identifier: containerId)
        self.database = container.privateCloudDatabase
    }
    
    public func uploadScan(_ scan: ScanHistoryManager.ScanVersion) async throws {
        let record = try createScanRecord(from: scan)
        
        do {
            _ = try await database.save(record)
            NotificationCenter.default.post(
                name: .scanUploadCompleted,
                object: nil,
                userInfo: ["scanId": scan.id]
            )
        } catch {
            NotificationCenter.default.post(
                name: .scanUploadFailed,
                object: nil,
                userInfo: [
                    "scanId": scan.id,
                    "error": error
                ]
            )
            throw SyncError.uploadFailed(error)
        }
    }
    
    public func downloadScan(id: UUID) async throws -> ScanHistoryManager.ScanVersion {
        let predicate = NSPredicate(format: "id == %@", id.uuidString)
        let query = CKQuery(recordType: "ScanVersion", predicate: predicate)
        
        do {
            let (records, _) = try await database.records(matching: query)
            guard let record = records.first?.1.get() else {
                throw SyncError.recordNotFound
            }
            
            return try createScanVersion(from: record)
        } catch {
            throw SyncError.downloadFailed(error)
        }
    }
    
    public func syncAllScans() async throws {
        let localScans = try await ScanHistoryManager().getScanHistory()
        
        // Upload local scans that aren't in the cloud
        for scan in localScans where scan.cloudBackupStatus != .completed {
            try await uploadScan(scan)
        }
        
        // Download cloud scans that aren't local
        let cloudScans = try await fetchAllCloudScans()
        let localIds = Set(localScans.map { $0.id })
        
        for scan in cloudScans where !localIds.contains(scan.id) {
            let downloaded = try await downloadScan(id: scan.id)
            try await ScanHistoryManager().saveToCoreData(downloaded)
        }
    }
    
    public func setupChangeNotifications() {
        let subscription = CKQuerySubscription(
            recordType: "ScanVersion",
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        Task {
            do {
                try await database.save(subscription)
            } catch {
                print("Failed to set up subscription: \(error)")
            }
        }
    }
    
    private func createScanRecord(from scan: ScanHistoryManager.ScanVersion) throws -> CKRecord {
        let record = CKRecord(recordType: "ScanVersion")
        record["id"] = scan.id.uuidString
        record["timestamp"] = scan.timestamp
        record["quality"] = scan.quality
        record["notes"] = scan.notes
        
        // Save thumbnail
        if let thumbnailData = scan.thumbnailData {
            let thumbnailURL = try saveTemporaryFile(thumbnailData)
            record["thumbnail"] = CKAsset(fileURL: thumbnailURL)
        }
        
        // Save mesh data
        let meshURL = try saveTemporaryFile(scan.meshData)
        record["meshData"] = CKAsset(fileURL: meshURL)
        
        record["exportFormats"] = scan.exportFormats.map { $0.rawValue }
        
        return record
    }
    
    private func createScanVersion(from record: CKRecord) throws -> ScanHistoryManager.ScanVersion {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let timestamp = record["timestamp"] as? Date,
              let quality = record["quality"] as? Float,
              let notes = record["notes"] as? String,
              let exportFormatStrings = record["exportFormats"] as? [String] else {
            throw SyncError.invalidRecord
        }
        
        // Get thumbnail data
        let thumbnailData: Data? = {
            guard let asset = record["thumbnail"] as? CKAsset,
                  let url = asset.fileURL else { return nil }
            return try? Data(contentsOf: url)
        }()
        
        // Get mesh data
        guard let meshAsset = record["meshData"] as? CKAsset,
              let meshURL = meshAsset.fileURL,
              let meshData = try? Data(contentsOf: meshURL) else {
            throw SyncError.invalidRecord
        }
        
        let exportFormats = exportFormatStrings.compactMap {
            ScanHistoryManager.ScanVersion.ExportFormat(rawValue: $0)
        }
        
        return ScanHistoryManager.ScanVersion(
            id: id,
            timestamp: timestamp,
            quality: quality,
            thumbnailData: thumbnailData,
            notes: notes,
            meshData: meshData,
            cloudBackupStatus: .completed,
            exportFormats: exportFormats
        )
    }
    
    private func fetchAllCloudScans() async throws -> [ScanHistoryManager.ScanVersion] {
        let query = CKQuery(
            recordType: "ScanVersion",
            predicate: NSPredicate(value: true)
        )
        
        var scans: [ScanHistoryManager.ScanVersion] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (records, newCursor) = try await database.records(
                matching: query,
                resultsLimit: 50,
                desiredKeys: nil,
                cursor: cursor
            )
            
            for record in records {
                if let scan = try? createScanVersion(from: record.1.get()) {
                    scans.append(scan)
                }
            }
            
            cursor = newCursor
        } while cursor != nil
        
        return scans
    }
    
    private func saveTemporaryFile(_ data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString)
        try data.write(to: fileURL)
        return fileURL
    }
}

// Notification names
extension Notification.Name {
    static let scanUploadCompleted = Notification.Name("scanUploadCompleted")
    static let scanUploadFailed = Notification.Name("scanUploadFailed")
}
