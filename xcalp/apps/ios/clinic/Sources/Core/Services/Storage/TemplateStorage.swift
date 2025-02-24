import CoreData
import Foundation

actor TemplateStorage {
    private let persistenceController: PersistenceController
    private let offlineQueue: OfflineOperationQueue
    
    init(persistenceController: PersistenceController = .shared,
         offlineQueue: OfflineOperationQueue = .shared) {
        self.persistenceController = persistenceController
        self.offlineQueue = offlineQueue
    }
    
    // MARK: - Template Operations
    func loadTemplates() async throws -> [TreatmentTemplate] {
        let context = persistenceController.container.viewContext
        let request = TemplateEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TemplateEntity.updatedAt, ascending: false)]
        
        let entities = try context.fetch(request)
        return try entities.map { try $0.toModel() }
    }
    
    func saveTemplate(_ template: TreatmentTemplate) async throws -> TreatmentTemplate {
        let context = persistenceController.container.newBackgroundContext()
        
        return try await context.perform {
            // Save current version as template
            let entity = try self.findOrCreateTemplateEntity(for: template.id, in: context)
            try self.update(entity: entity, with: template)
            
            // Save version history
            let versionEntity = TemplateVersionEntity(context: context)
            versionEntity.id = UUID()
            versionEntity.templateId = template.id
            versionEntity.version = Int32(template.version)
            versionEntity.createdAt = Date()
            versionEntity.parametersData = try JSONEncoder().encode(template.parameters)
            versionEntity.regionsData = try JSONEncoder().encode(template.regions)
            
            try context.save()
            
            // Queue sync operation if offline
            if NetworkMonitor.shared.isOffline {
                try await self.queueTemplateSync(template)
            }
            
            return template
        }
    }
    
    func deleteTemplate(_ id: UUID) async throws -> Bool {
        let context = persistenceController.container.newBackgroundContext()
        
        return try await context.perform {
            let request = TemplateEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                return false
            }
            
            context.delete(entity)
            try context.save()
            
            // Queue delete operation if offline
            if NetworkMonitor.shared.isOffline {
                try await self.queueTemplateDeletion(id)
            }
            
            return true
        }
    }
    
    func loadVersionHistory(_ templateId: UUID) async throws -> [TreatmentTemplate] {
        let context = persistenceController.container.viewContext
        let request = TemplateVersionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "templateId == %@", templateId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TemplateVersionEntity.version, ascending: false)]
        
        let versions = try context.fetch(request)
        return try versions.map { try $0.toModel() }
    }
    
    func restoreVersion(_ template: TreatmentTemplate) async throws -> TreatmentTemplate {
        // Create new version from old one
        var restoredTemplate = template
        restoredTemplate.version += 1
        restoredTemplate.updatedAt = Date()
        
        return try await saveTemplate(restoredTemplate)
    }
    
    // MARK: - Sync Operations
    func syncPendingChanges() async throws {
        let operations = try await offlineQueue.getPendingOperations(ofType: .template)
        
        for operation in operations {
            do {
                switch operation.action {
                case .create, .update:
                    let template = try JSONDecoder().decode(TreatmentTemplate.self, from: operation.data)
                    _ = try await APIClient.shared.syncTemplate(template)
                case .delete:
                    let id = try JSONDecoder().decode(UUID.self, from: operation.data)
                    try await APIClient.shared.deleteTemplate(id)
                }
                try await offlineQueue.markOperationCompleted(operation.id)
            } catch {
                logger.error("Failed to sync template operation: \(error.localizedDescription)")
                // Continue with next operation
                continue
            }
        }
    }
    
    // MARK: - Private Helpers
    private func findOrCreateTemplateEntity(for id: UUID, in context: NSManagedObjectContext) throws -> TemplateEntity {
        let request = TemplateEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        return try context.fetch(request).first ?? TemplateEntity(context: context)
    }
    
    private func update(entity: TemplateEntity, with template: TreatmentTemplate) throws {
        entity.id = template.id
        entity.name = template.name
        entity.templateDescription = template.description
        entity.version = Int32(template.version)
        entity.createdAt = template.createdAt
        entity.updatedAt = template.updatedAt
        entity.author = template.author
        entity.isCustom = template.isCustom
        entity.parentTemplateId = template.parentTemplateId
        
        // Encode parameters and regions
        let encoder = JSONEncoder()
        entity.parametersData = try encoder.encode(template.parameters)
        entity.regionsData = try encoder.encode(template.regions)
    }
    
    private func queueTemplateSync(_ template: TreatmentTemplate) async throws {
        let data = try JSONEncoder().encode(template)
        let operation = OfflineOperation(
            id: UUID(),
            type: .template,
            action: .update,
            data: data,
            timestamp: Date()
        )
        try await offlineQueue.addOperation(operation)
    }
    
    private func queueTemplateDeletion(_ id: UUID) async throws {
        let data = try JSONEncoder().encode(id)
        let operation = OfflineOperation(
            id: UUID(),
            type: .template,
            action: .delete,
            data: data,
            timestamp: Date()
        )
        try await offlineQueue.addOperation(operation)
    }
}

// MARK: - CoreData Entity Extension
extension TemplateEntity {
    func toModel() throws -> TreatmentTemplate {
        let decoder = JSONDecoder()
        
        let parameters = try decoder.decode([TreatmentTemplate.Parameter].self, from: parametersData ?? Data())
        let regions = try decoder.decode([TreatmentRegion].self, from: regionsData ?? Data())
        
        return TreatmentTemplate(
            id: id ?? UUID(),
            name: name ?? "",
            description: templateDescription ?? "",
            version: Int(version),
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            parameters: parameters,
            regions: regions,
            author: author ?? "",
            isCustom: isCustom,
            parentTemplateId: parentTemplateId
        )
    }
}
