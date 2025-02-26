import Foundation
import CoreML

actor MLModelLoader {
    static let shared = MLModelLoader()
    
    private var loadedModels: [String: MLModel] = [:]
    private var loadingTasks: [String: Task<MLModel, Error>] = [:]
    private let modelManager = ModelManager.shared
    private let cache = MLModelCache()
    
    private init() {}
    
    func loadModel(named name: String) async throws -> MLModel {
        // Return cached model if available
        if let model = loadedModels[name] {
            return model
        }
        
        // Check if there's already a loading task
        if let existingTask = loadingTasks[name] {
            return try await existingTask.value
        }
        
        // Create new loading task
        let task = Task {
            // Try to load from memory cache first
            if let cachedModel = try? await cache.loadFromCache(name) {
                loadedModels[name] = cachedModel
                return cachedModel
            }
            
            // Load latest model version
            let model = try await modelManager.loadLatestModel(named: name)
            
            // Cache the model
            await cache.cacheModel(model, named: name)
            loadedModels[name] = model
            
            return model
        }
        
        loadingTasks[name] = task
        
        do {
            let model = try await task.value
            loadingTasks[name] = nil
            return model
        } catch {
            loadingTasks[name] = nil
            throw error
        }
    }
    
    func preloadModels(_ modelNames: [String]) {
        for name in modelNames {
            Task {
                try? await loadModel(named: name)
            }
        }
    }
    
    func unloadModel(_ name: String) {
        loadedModels.removeValue(forKey: name)
        loadingTasks[name]?.cancel()
        loadingTasks.removeValue(forKey: name)
    }
    
    func clearCache() async {
        await cache.clearCache()
        loadedModels.removeAll()
    }
}

private actor MLModelCache {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init() {
        let cachePath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachePath.appendingPathComponent("MLModels")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func loadFromCache(_ name: String) async throws -> MLModel {
        let modelURL = cacheDirectory.appendingPathComponent("\(name).mlmodelc")
        
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw CacheError.modelNotFound
        }
        
        return try MLModel(contentsOf: modelURL)
    }
    
    func cacheModel(_ model: MLModel, named name: String) async {
        let modelURL = cacheDirectory.appendingPathComponent("\(name).mlmodelc")
        
        do {
            // Save model to cache directory
            if let modelPath = model.modelDescription.modelPath {
                try fileManager.copyItem(atPath: modelPath, toPath: modelURL.path)
            }
        } catch {
            print("Failed to cache model: \(error)")
        }
    }
    
    func clearCache() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

enum CacheError: Error {
    case modelNotFound
    case saveFailed
}