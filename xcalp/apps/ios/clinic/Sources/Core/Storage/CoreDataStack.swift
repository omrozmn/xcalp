import CoreData
import Foundation

public final class CoreDataStack {
    public static let shared = CoreDataStack()
    
    public var backgroundContext: NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.parent = mainContext
        return context
    }
    
    public var mainContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "XcalpClinic")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()
}