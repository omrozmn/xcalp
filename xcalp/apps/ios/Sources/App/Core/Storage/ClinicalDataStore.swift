import Foundation
import CoreData
import CryptoKit
import AppKit

final class ClinicalDataStore {
    static let shared = ClinicalDataStore()

    private let errorHandler = XCErrorHandler.shared
    private let performanceMonitor = XCPerformanceMonitor.shared
    
    // MARK: - Core Data
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "XcalpClinic")
        
        // Configure persistent store encryption
        let storeDescription = container.persistentStoreDescriptions.first
        storeDescription?.setOption(true as NSNumber, forKey: NSPersistentStoreFileProtectionKey)
        
        container.loadPersistentStores { description, error in
            if let error = error {
                self.errorHandler.handle(error, severity: .critical)
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        
        // Enable data protection
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        return container
    }()
    
    // MARK: - Scan Data Operations
    func storeScan(_ scanData: ScanData) throws {
        performanceMonitor.startMeasuring("ScanDataStorage")
        
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        context.performAndWait {
            do {
                // Encrypt sensitive data
                let encryptedData = try encryptScanData(scanData)
                
                // Create managed object
                let scanEntity = ScanEntity(context: context)
                scanEntity.id = scanData.id
                scanEntity.timestamp = scanData.timestamp
                scanEntity.patientId = scanData.patientId
                scanEntity.scanType = scanData.scanType.rawValue
                scanEntity.encryptedData = encryptedData
                scanEntity.metadata = try JSONEncoder().encode(scanData.processingMetadata)
                
                // Save quality metrics separately for querying
                let metricsEntity = QualityMetricsEntity(context: context)
                metricsEntity.scanId = scanData.id
                metricsEntity.pointDensity = scanData.qualityMetrics.pointDensity
                metricsEntity.surfaceCompleteness = scanData.qualityMetrics.surfaceCompleteness
                metricsEntity.noiseLevel = scanData.qualityMetrics.noiseLevel
                metricsEntity.featurePreservation = scanData.qualityMetrics.featurePreservation
                
                // Create audit trail
                let auditEntity = AuditEntity(context: context)
                auditEntity.action = "store_scan"
                auditEntity.scanId = scanData.id
                auditEntity.userId = getCurrentUserId()
                
                try context.save()
                
            } catch {
                context.rollback()
                self.errorHandler.handle(error, severity: .high)
                throw error
            }
        }
        
        performanceMonitor.stopMeasuring("ScanDataStorage")
    }
    
    func retrieveScan(id: UUID) throws -> ScanData {
        let context = persistentContainer.viewContext
        
        guard let scanEntity = try fetchScanEntity(id: id, in: context),
              let encryptedData = scanEntity.encryptedData,
              let metadata = scanEntity.metadata else {
            throw StorageError.scanNotFound
        }
        
        do {
            // Decrypt data
            let decryptedData = try decryptScanData(encryptedData)
            
            // Create audit trail
            let auditEntity = AuditEntity(context: context)
            auditEntity.timestamp = Date()
            auditEntity.action = "retrieve_scan"
            auditEntity.scanId = id
            auditEntity.userId = getCurrentUserId()
            
            try context.save()
            
            // Decode scan data
            return try JSONDecoder().decode(ScanData.self, from: decryptedData)
            
        } catch {
            self.errorHandler.handle(error, severity: .medium)
            throw error
        }
    }
    
    func fetchScanHistory(patientId: String, limit: Int = 10) throws -> [ScanData] {
        let context = persistentContainer.viewContext
        
        let fetchRequest: NSFetchRequest<ScanEntity> = ScanEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "patientId == %@", patientId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = limit
        
        do {
            let scanEntities = try context.fetch(fetchRequest)
            return try scanEntities.compactMap { entity in
                guard let encryptedData = entity.encryptedData else {
                    return nil
                }
                
                let decryptedData = try decryptScanData(encryptedData)
                return try JSONDecoder().decode(ScanData.self, from: decryptedData)
            }
        } catch {
            self.errorHandler.handle(error, severity: .medium)
            throw error
        }
    }
    
    // MARK: - Quality Metrics Queries
    func fetchScansRequiringAttention() throws -> [UUID] {
        let context = persistentContainer.viewContext
        
        let fetchRequest: NSFetchRequest<QualityMetricsEntity> = QualityMetricsEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "surfaceCompleteness < 98 OR noiseLevel > 0.1 OR featurePreservation < 95")
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.compactMap { $0.scanId }
        } catch {
            self.errorHandler.handle(error, severity: .low)
            throw error
        }
    }
    
    // MARK: - Encryption
    private func encryptScanData(_ scanData: ScanData) throws -> Data {
        let jsonData = try JSONEncoder().encode(scanData)
        
        // Generate a new key for each scan
        let key = SymmetricKey(size: .bits256)
        
        // Store the key securely (implementation depends on your key management strategy)
        try storeEncryptionKey(key, forScanId: scanData.id)
        
        // Encrypt the data
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        return sealedBox.combined!
    }
    
    private func decryptScanData(_ encryptedData: Data) throws -> Data {
        // Retrieve the key (implementation depends on your key management strategy)
        guard let key = try retrieveEncryptionKey(forScanId: scanData.id) else {
            throw StorageError.keyNotFound
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // MARK: - Helper Methods
    private func fetchScanEntity(id: UUID, in context: NSManagedObjectContext) throws -> ScanEntity? {
        let fetchRequest: NSFetchRequest<ScanEntity> = ScanEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(fetchRequest).first
    }
    
    private func getCurrentUserId() -> String {
        // Implementation depends on your authentication system
        return "current_user_id"
    }
}

enum StorageError: Error {
    case scanNotFound
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case invalidData
    case saveFailed
}