import Dependencies
import Foundation

extension ScanModelManager: DependencyKey {
    static var liveValue: ScanModelManager = {
        return ScanModelManager()
    }()
}

extension DependencyValues {
    var scanModelManager: ScanModelManager {
        get { self[ScanModelManager.self] }
        set { self[ScanModelManager.self] = newValue }
    }
}