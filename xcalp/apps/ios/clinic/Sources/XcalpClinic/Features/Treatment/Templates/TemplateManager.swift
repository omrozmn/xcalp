import Foundation
import ComposableArchitecture

@Observable
class TemplateManager {
    private(set) var templates: [TreatmentTemplate] = []
    private let storage: TemplateStorage
    
    init(storage: TemplateStorage = DefaultTemplateStorage()) {
        self.storage = storage
        loadTemplates()
    }
    
    func loadTemplates() {
        templates = storage.loadTemplates()
    }
    
    func saveTemplate(_ template: TreatmentTemplate) throws {
        try storage.saveTemplate(template)
        loadTemplates()
    }
    
    func deleteTemplate(_ template: TreatmentTemplate) throws {
        try storage.deleteTemplate(template)
        loadTemplates()
    }
    
    func updateTemplate(_ template: TreatmentTemplate) throws {
        try storage.updateTemplate(template)
        loadTemplates()
    }
}

protocol TemplateStorage {
    func loadTemplates() -> [TreatmentTemplate]
    func saveTemplate(_ template: TreatmentTemplate) throws
    func deleteTemplate(_ template: TreatmentTemplate) throws
    func updateTemplate(_ template: TreatmentTemplate) throws
}

class DefaultTemplateStorage: TemplateStorage {
    private let fileManager = FileManager.default
    private let documentsPath: URL
    
    init() {
        documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TreatmentTemplates")
        try? fileManager.createDirectory(at: documentsPath, withIntermediateDirectories: true)
    }
    
    func loadTemplates() -> [TreatmentTemplate] {
        guard let files = try? fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let template = try? JSONDecoder().decode(TreatmentTemplate.self, from: data) else {
                return nil
            }
            return template
        }
    }
    
    func saveTemplate(_ template: TreatmentTemplate) throws {
        let data = try JSONEncoder().encode(template)
        let fileURL = documentsPath.appendingPathComponent("\(template.id.uuidString).json")
        try data.write(to: fileURL)
    }
    
    func deleteTemplate(_ template: TreatmentTemplate) throws {
        let fileURL = documentsPath.appendingPathComponent("\(template.id.uuidString).json")
        try fileManager.removeItem(at: fileURL)
    }
    
    func updateTemplate(_ template: TreatmentTemplate) throws {
        try saveTemplate(template)
    }
}