import Foundation
import CoreData

@objc(ScanEntity)
public class ScanEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var patientId: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var quality: Float
    @NSManaged public var meshData: Data?
    @NSManaged public var notes: String?
    @NSManaged public var metadata: Data?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var patient: Patient?
    @NSManaged public var treatments: NSSet?
}

// MARK: Generated accessors for treatments
extension ScanEntity {
    @objc(addTreatmentsObject:)
    @NSManaged public func addToTreatments(_ value: Treatment)
    
    @objc(removeTreatmentsObject:)
    @NSManaged public func removeFromTreatments(_ value: Treatment)
    
    @objc(addTreatments:)
    @NSManaged public func addToTreatments(_ values: NSSet)
    
    @objc(removeTreatments:)
    @NSManaged public func removeFromTreatments(_ values: NSSet)
}

extension ScanEntity: Identifiable {}
