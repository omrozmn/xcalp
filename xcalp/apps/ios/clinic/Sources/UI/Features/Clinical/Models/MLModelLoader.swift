import CoreML
import Foundation

public final class MLModelLoader {
    public enum ModelLoadingError: Error {
        case modelNotFound
    }
    
    public static let shared = MLModelLoader()
    
    private var loadedModels: [String: MLModel] = [:]
    
    private init() {}
    
    public func loadModel(named modelName: String) async throws -> MLModel {
        if let cachedModel = loadedModels[modelName] {
            return cachedModel
        }
        
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw ModelLoadingError.modelNotFound
        }
        let model = try MLModel(contentsOf: modelURL, configuration: config)
        
        loadedModels[modelName] = model
        return model
    }
    
    public func preloadModels(_ modelNames: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for modelName in modelNames {
                group.addTask {
                    _ = try? await self.loadModel(named: modelName)
                }
            }
        }
    }
}
