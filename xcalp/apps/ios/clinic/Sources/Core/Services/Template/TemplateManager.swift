import Dependencies
import Foundation

actor TemplateManager {
    private let templateClient: TemplateClient
    private let exportManager: TemplateExportManager
    
    init(templateClient: TemplateClient, exportManager: TemplateExportManager = TemplateExportManager()) {
        self.templateClient = templateClient
        self.exportManager = exportManager
    }
    
    // MARK: - Template Management
    func createTemplate(
        name: String,
        description: String,
        parameters: TreatmentTemplate.TemplateParameters,
        regions: [TreatmentRegion],
        author: String,
        parentTemplateId: UUID? = nil
    ) async throws -> TreatmentTemplate {
        let template = TreatmentTemplate(
            id: UUID(),
            name: name,
            description: description,
            version: 1,
            createdAt: Date(),
            updatedAt: Date(),
            parameters: parameters,
            regions: regions,
            author: author,
            isCustom: true,
            parentTemplateId: parentTemplateId
        )
        
        return try await templateClient.saveTemplate(template)
    }
    
    func cloneTemplate(_ template: TreatmentTemplate, newName: String) async throws -> TreatmentTemplate {
        return try await createTemplate(
            name: newName,
            description: "Cloned from \(template.name)",
            parameters: template.parameters,
            regions: template.regions,
            author: template.author,
            parentTemplateId: template.id
        )
    }
    
    func modifyTemplate(
        _ template: TreatmentTemplate,
        parameters: TreatmentTemplate.TemplateParameters? = nil,
        regions: [TreatmentRegion]? = nil,
        description: String? = nil
    ) async throws -> TreatmentTemplate {
        let updatedTemplate = TreatmentTemplate(
            id: template.id,
            name: template.name,
            description: description ?? template.description,
            version: template.version + 1,
            createdAt: template.createdAt,
            updatedAt: Date(),
            parameters: parameters ?? template.parameters,
            regions: regions ?? template.regions,
            author: template.author,
            isCustom: template.isCustom,
            parentTemplateId: template.parentTemplateId
        )
        
        return try await templateClient.saveTemplate(updatedTemplate)
    }
    
    // MARK: - Template Queries
    func loadTemplates() async throws -> [TreatmentTemplate] {
        return try await templateClient.loadTemplates()
    }
    
    func getTemplateHistory(_ templateId: UUID) async throws -> [TreatmentTemplate] {
        let templates = try await loadTemplates()
        var current = templates.first { $0.id == templateId }
        var history: [TreatmentTemplate] = []
        
        while let template = current {
            history.append(template)
            current = template.parentTemplateId.flatMap { parentId in
                templates.first { $0.id == parentId }
            }
        }
        
        return history
    }
    
    func getCustomTemplates() async throws -> [TreatmentTemplate] {
        let templates = try await loadTemplates()
        return templates.filter { $0.isCustom }
    }
    
    func getStandardTemplates() async throws -> [TreatmentTemplate] {
        let templates = try await loadTemplates()
        return templates.filter { !$0.isCustom }
    }
    
    // MARK: - Template Validation
    func validateTemplate(_ template: TreatmentTemplate) -> Bool {
        // Basic validation
        guard !template.name.isEmpty,
              !template.description.isEmpty,
              !template.regions.isEmpty else {
            return false
        }
        
        // Validate parameters
        guard template.parameters.targetDensity > 0,
              template.parameters.graftSpacing > 0,
              template.parameters.angleVariation >= 0,
              template.parameters.naturalness >= 0 else {
            return false
        }
        
        // Validate regions
        for region in template.regions {
            guard region.boundaries.count >= 3,  // Minimum 3 points for a valid region
                  region.parameters.density > 0,
                  region.parameters.depth > 0 else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Template Import/Export
    func exportTemplate(_ template: TreatmentTemplate, to url: URL) async throws {
        try await exportManager.exportTemplate(template, to: url)
    }
    
    func exportTemplates(_ templates: [TreatmentTemplate], to url: URL) async throws {
        try await exportManager.exportTemplates(templates, to: url)
    }
    
    func importTemplate(from url: URL) async throws -> TreatmentTemplate {
        let template = try await exportManager.importTemplate(from: url)
        return try await templateClient.saveTemplate(template)
    }
    
    func importTemplates(from url: URL) async throws -> [TreatmentTemplate] {
        let templates = try await exportManager.importTemplates(from: url)
        var importedTemplates: [TreatmentTemplate] = []
        
        for template in templates {
            importedTemplates.append(try await templateClient.saveTemplate(template))
        }
        
        return importedTemplates
    }
    
    func createBackup() async throws -> URL {
        let templates = try await loadTemplates()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupsURL = documentsURL.appendingPathComponent("Backups", isDirectory: true)
        
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        
        return try await exportManager.createBackup(of: templates, to: backupsURL)
    }
}