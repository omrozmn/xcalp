import Dependencies
import Foundation

struct TemplateClient {
    var loadTemplates: () async throws -> [TreatmentTemplate]
    var saveTemplate: (TreatmentTemplate) async throws -> TreatmentTemplate
    var deleteTemplate: (UUID) async throws -> Bool
}

extension TemplateClient: DependencyKey {
    static var liveValue: TemplateClient = {
        let storage = TemplateStorage()
        
        return Self(
            loadTemplates: {
                try await storage.loadTemplates()
            },
            saveTemplate: { template in
                try await storage.saveTemplate(template)
            },
            deleteTemplate: { id in
                try await storage.deleteTemplate(id)
            }
        )
    }()
}

extension DependencyValues {
    var templateClient: TemplateClient {
        get { self[TemplateClient.self] }
        set { self[TemplateClient.self] = newValue }
    }
}

// MARK: - Storage Implementation
private actor TemplateStorage {
    private var templates: [TreatmentTemplate] = []
    private let storage = SecureStorage.shared
    private let key = "treatment_templates"
    
    func loadTemplates() async throws -> [TreatmentTemplate] {
        if templates.isEmpty {
            templates = try await storage.load([TreatmentTemplate].self, forKey: key) ?? []
        }
        return templates
    }
    
    func saveTemplate(_ template: TreatmentTemplate) async throws -> TreatmentTemplate {
        var updatedTemplate = template
        
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            // Update existing template
            updatedTemplate = TreatmentTemplate(
                id: template.id,
                name: template.name,
                description: template.description,
                version: template.version + 1,
                createdAt: templates[index].createdAt,
                updatedAt: Date(),
                parameters: template.parameters,
                regions: template.regions,
                author: template.author,
                isCustom: template.isCustom,
                parentTemplateId: template.parentTemplateId
            )
            templates[index] = updatedTemplate
        } else {
            // Add new template
            templates.append(template)
        }
        
        try await storage.save(templates, forKey: key)
        return updatedTemplate
    }
    
    func deleteTemplate(_ id: UUID) async throws -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            return false
        }
        
        templates.remove(at: index)
        try await storage.save(templates, forKey: key)
        return true
    }
}
