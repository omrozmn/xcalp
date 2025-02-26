import Foundation
import CoreData

@objc(DashboardCache)
public class DashboardCache: NSManagedObject {
    @NSManaged public var timestamp: Date?
    @NSManaged public var summary: Data?
    @NSManaged public var stats: Data?
    
    public static func fetchMostRecent(in context: NSManagedObjectContext) throws -> DashboardCache? {
        let request = NSFetchRequest<DashboardCache>(entityName: "DashboardCache")
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}