import Foundation
import CoreData
import Dependencies

public struct OfflineStorage {
    public var storeOperation: @Sendable (ProcessingOperation) async throws -> Void
    public var markOperationCompleted: @Sendable (ProcessingOperation) async throws -> Void
    public var getQueuedOperations: @Sendable () async throws -> [ProcessingOperation]
    public var clearCompletedOperations: @Sendable () async throws -> Void
    
    public static let liveValue = Self.live
    
    static let live = Self(
        storeOperation: { operation in
            let context = PersistenceController.shared.container.newBackgroundContext()
            
            try await context.perform {
                let operationEntity = OperationEntity(context: context)
                operationEntity.id = operation.id
                operationEntity.type = operation.type.rawValue
                operationEntity.data = operation.data
                operationEntity.timestamp = operation.timestamp
                operationEntity.completed = false
                
                try context.save()
            }
        },
        markOperationCompleted: { operation in
            let context = PersistenceController.shared.container.newBackgroundContext()
            let fetchRequest: NSFetchRequest<OperationEntity> = OperationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", operation.id as CVarArg)
            
            try await context.perform {
                let results = try context.fetch(fetchRequest)
                guard let operationEntity = results.first else { return }
                operationEntity.completed = true
                try context.save()
            }
        },
        getQueuedOperations: {
            let context = PersistenceController.shared.container.newBackgroundContext()
            let fetchRequest: NSFetchRequest<OperationEntity> = OperationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "completed == NO")
            
            return try await context.perform {
                let results = try context.fetch(fetchRequest)
                return results.map { entity in
                    ProcessingOperation(
                        id: entity.id,
                        type: ProcessingOperation.ProcessingOperationType(rawValue: entity.type) ?? .scan,
                        data: entity.data,
                        timestamp: entity.timestamp
                    )
                }
            }
        },
        clearCompletedOperations: {
            let context = PersistenceController.shared.container.newBackgroundContext()
            let fetchRequest: NSFetchRequest<OperationEntity> = OperationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "completed == YES")
            
            try await context.perform {
                let results = try context.fetch(fetchRequest)
                for operation in results {
                    context.delete(operation)
                }
                try context.save()
            }
        }
    )
}

extension DependencyValues {
    public var offlineStorage: OfflineStorage {
        get { self[OfflineStorage.self] }
        set { self[OfflineStorage.self] = newValue }
    }
}

private class OperationEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var type: String
    @NSManaged var data: Data
    @NSManaged var timestamp: Date
    @NSManaged var completed: Bool
}
