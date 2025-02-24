import Foundation

enum TemplateExportError: Error {
    case encodingFailed
    case decodingFailed
    case invalidFile
}

actor TemplateExportManager {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func exportTemplate(_ template: TreatmentTemplate, to url: URL) async throws {
        let data = try encoder.encode(template)
        try data.write(to: url)
    }
    
    func exportTemplates(_ templates: [TreatmentTemplate], to url: URL) async throws {
        let data = try encoder.encode(templates)
        try data.write(to: url)
    }
    
    func importTemplate(from url: URL) async throws -> TreatmentTemplate {
        let data = try Data(contentsOf: url)
        return try decoder.decode(TreatmentTemplate.self, from: data)
    }
    
    func importTemplates(from url: URL) async throws -> [TreatmentTemplate] {
        let data = try Data(contentsOf: url)
        return try decoder.decode([TreatmentTemplate].self, from: data)
    }
    
    func createBackup(of templates: [TreatmentTemplate], to directory: URL) async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let backupURL = directory.appendingPathComponent("templates_backup_\(timestamp).json")
        try await exportTemplates(templates, to: backupURL)
        
        return backupURL
    }
}
