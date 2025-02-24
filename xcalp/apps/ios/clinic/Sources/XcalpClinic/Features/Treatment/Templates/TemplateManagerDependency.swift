import ComposableArchitecture
import Dependencies
import Foundation

private enum TemplateManagerKey: DependencyKey {
    static let liveValue: TemplateManager = TemplateManager(storage: DefaultTemplateStorage())
    static let testValue: TemplateManager = TemplateManager(storage: DefaultTemplateStorage())
}

extension DependencyValues {
    var templateManager: TemplateManager {
        get { self[TemplateManagerKey.self] }
        set { self[TemplateManagerKey.self] = newValue }
    }
}
