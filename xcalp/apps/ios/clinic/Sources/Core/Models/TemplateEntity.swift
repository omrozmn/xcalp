import CoreData

@objc(TemplateEntity)
public class TemplateEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var templateDescription: String?
    @NSManaged public var version: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var author: String?
    @NSManaged public var isCustom: Bool
    @NSManaged public var parentTemplateId: UUID?
    @NSManaged public var parametersData: Data?
    @NSManaged public var regionsData: Data?
}

extension TemplateEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TemplateEntity> {
        NSFetchRequest<TemplateEntity>(entityName: "TemplateEntity")
    }
}
