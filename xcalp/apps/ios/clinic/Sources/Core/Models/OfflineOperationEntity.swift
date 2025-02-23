import CoreData

@objc(OfflineOperationEntity)
public class OfflineOperationEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var type: String?
    @NSManaged public var action: String?
    @NSManaged public var data: Data?
    @NSManaged public var timestamp: Date?
    @NSManaged public var isCompleted: Bool
}

extension OfflineOperationEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<OfflineOperationEntity> {
        return NSFetchRequest<OfflineOperationEntity>(entityName: "OfflineOperationEntity")
    }
}