import Foundation
import ComposableArchitecture
import Dependencies

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