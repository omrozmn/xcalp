import Foundation
import CoreData

public enum StorageError: Error {
    case saveFailed
    case fetchFailed
    case deleteFailed
    case invalidData
    case contextError
}

public final class StorageManager {
    public static let shared = StorageManager()
    
    private let logger = XcalpLogger.shared
    private let security = SecurityManager.shared
    
    // MARK: - Core Data Stack
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "XcalpClinic")
        
        // Enable encryption for HIPAA compliance
        let storeDescription = container.persistentStoreDescriptions.first
        storeDescription?.setOption(FileProtectionType.complete as NSObject,
                                  forKey: NSPersistentStoreFileProtectionKey)
        
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                self?.logger.log(.error, message: "Failed to load Core Data stack: \(error.localizedDescription)")
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        
        // Enable automatic merging of changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    private var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    // MARK: - CRUD Operations
    public func create<T: NSManagedObject>(_ type: T.Type, attributes: [String: Any]) throws -> T {
        let object = T(context: context)
        
        for (key, value) in attributes {
            // Encrypt sensitive data before saving
            if let sensitiveData = value as? Data {
                let encryptedData = try security.encryptData(sensitiveData)
                object.setValue(encryptedData, forKey: key)
            } else {
                object.setValue(value, forKey: key)
            }
        }
        
        try save()
        return object
    }
    
    public func fetch<T: NSManagedObject>(_ type: T.Type,
                                         predicate: NSPredicate? = nil,
                                         sortDescriptors: [NSSortDescriptor]? = nil) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        
        do {
            let results = try context.fetch(request)
            
            // Decrypt sensitive data
            return try results.map { object in
                let decryptedObject = object
                for property in object.entity.properties {
                    if property.isEncrypted,
                       let encryptedData = object.value(forKey: property.name) as? Data {
                        let decryptedData = try security.decryptData(encryptedData)
                        decryptedObject.setValue(decryptedData, forKey: property.name)
                    }
                }
                return decryptedObject
            }
        } catch {
            logger.log(.error, message: "Fetch failed: \(error.localizedDescription)")
            throw StorageError.fetchFailed
        }
    }
    
    public func update<T: NSManagedObject>(_ object: T, attributes: [String: Any]) throws {
        for (key, value) in attributes {
            // Encrypt sensitive data before saving
            if let sensitiveData = value as? Data {
                let encryptedData = try security.encryptData(sensitiveData)
                object.setValue(encryptedData, forKey: key)
            } else {
                object.setValue(value, forKey: key)
            }
        }
        
        try save()
    }
    
    public func delete<T: NSManagedObject>(_ object: T) throws {
        context.delete(object)
        try save()
    }
    
    private func save() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                logger.log(.error, message: "Save failed: \(error.localizedDescription)")
                throw StorageError.saveFailed
            }
        }
    }
    
    // MARK: - Background Operations
    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) throws -> Void) {
        persistentContainer.performBackgroundTask { context in
            do {
                try block(context)
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                self.logger.log(.error, message: "Background task failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - iCloud Sync
    public func enableCloudSync() {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else {
            return
        }
        
        let options = [
            NSPersistentStoreUbiquitousContentNameKey: "XcalpClinicCloud",
            NSPersistentStoreUbiquitousContainerIdentifierKey: "com.xcalp.clinic",
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: true
        ] as [String: Any]
        
        do {
            try persistentContainer.persistentStoreCoordinator.setOptions(options, for: storeURL)
            logger.log(.info, message: "iCloud sync enabled")
        } catch {
            logger.log(.error, message: "Failed to enable iCloud sync: \(error.localizedDescription)")
        }
    }
}

// MARK: - NSPropertyDescription Extension
private extension NSPropertyDescription {
    var isEncrypted: Bool {
        // Check if property should be encrypted based on user info
        userInfo?["encrypted"] as? Bool ?? false
    }
}
