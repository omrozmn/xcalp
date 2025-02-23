import Dependencies
import Foundation

extension TemplateManager: DependencyKey {
    static var liveValue: TemplateManager = {
        let templateClient = TemplateClient.liveValue
        let exportManager = TemplateExportManager()
        return TemplateManager(templateClient: templateClient, exportManager: exportManager)
    }()
}

extension DependencyValues {
    var templateManager: TemplateManager {
        get { self[TemplateManager.self] }
        set { self[TemplateManager.self] = newValue }
    }
}