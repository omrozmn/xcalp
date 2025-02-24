import CoreData
import Foundation

actor OfflineOperationQueue {
    static let shared = OfflineOperationQueue()
    
    enum OperationType: String {
        case template
        case scan
        case treatment
    }
    
    enum OperationAction: String {
        case create
        case update
        case delete
    }
    
    struct OfflineOperation: Identifiable {
        let id: UUID
        let type: OperationType
        let action: OperationAction
        let data: Data
        let timestamp: Date
        var isCompleted: Bool = false
    }
    
    private let persistenceController: PersistenceController
    
    private init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }
    
    func addOperation(_ operation: OfflineOperation) async throws {
        let context = persistenceController.container.newBackgroundContext()
        
        try await context.perform {
            let entity = OfflineOperationEntity(context: context)
            entity.id = operation.id
            entity.type = operation.type.rawValue
            entity.action = operation.action.rawValue
            entity.data = operation.data
            entity.timestamp = operation.timestamp
            entity.isCompleted = operation.isCompleted
            
            try context.save()
        }
    }
    
    func getPendingOperations(ofType type: OperationType? = nil) async throws -> [OfflineOperation] {
        let context = persistenceController.container.viewContext
        let request = OfflineOperationEntity.fetchRequest()
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "isCompleted == NO")
        ]
        
        if let type = type {
            predicates.append(NSPredicate(format: "type == %@", type.rawValue))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OfflineOperationEntity.timestamp, ascending: true)]
        
        let entities = try context.fetch(request)
        return entities.map { entity in
            OfflineOperation(
                id: entity.id ?? UUID(),
                type: OperationType(rawValue: entity.type ?? "") ?? .template,
                action: OperationAction(rawValue: entity.action ?? "") ?? .update,
                data: entity.data ?? Data(),
                timestamp: entity.timestamp ?? Date(),
                isCompleted: entity.isCompleted
            )
        }
    }
    
    func markOperationCompleted(_ operationId: UUID) async throws {
        let context = persistenceController.container.newBackgroundContext()
        
        try await context.perform {
            let request = OfflineOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", operationId as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                return
            }
            
            entity.isCompleted = true
            try context.save()
        }
    }
    
    func clearCompletedOperations() async throws {
        let context = persistenceController.container.newBackgroundContext()
        
        try await context.perform {
            let request = OfflineOperationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES")
            
            let entities = try context.fetch(request)
            entities.forEach { context.delete($0) }
            try context.save()
        }
    }
}
