import Foundation
import CoreML

public final class ModelManager {
    public static let shared = ModelManager()
    
    private let modelVersion = "1.0.0"
    private let minimumRequiredVersion = "1.0.0"
    private let modelUpdateURL = URL(string: "https://api.xcalp.com/ml/models")!
    
    public func loadLatestModel(named name: String) async throws -> MLModel {
        // Check if we have a cached model first
        if let cachedModel = try loadCachedModel(named: name) {
            return cachedModel
        }
        
        // Download latest model if needed
        let modelURL = try await downloadLatestModel(named: name)
        return try MLModel(contentsOf: modelURL)
    }
    
    public func checkForUpdates() async throws -> [ModelUpdate] {
        let localVersions = getLocalModelVersions()
        let updates = try await fetchAvailableUpdates()
        
        return updates.filter { update in
            guard let localVersion = localVersions[update.name] else { return true }
            return compareVersions(update.version, isNewerThan: localVersion)
        }
    }
    
    private func loadCachedModel(named name: String) throws -> MLModel? {
        let cacheURL = try modelCacheDirectory()
            .appendingPathComponent(name)
            .appendingPathExtension("mlmodelc")
        
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        
        return try MLModel(contentsOf: cacheURL)
    }
    
    private func downloadLatestModel(named name: String) async throws -> URL {
        var request = URLRequest(url: modelUpdateURL.appendingPathComponent(name))
        request.httpMethod = "GET"
        request.setValue(modelVersion, forHTTPHeaderField: "X-Model-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }
        
        // Save model to cache
        let cacheURL = try modelCacheDirectory()
            .appendingPathComponent(name)
            .appendingPathExtension("mlmodelc")
        
        try data.write(to: cacheURL)
        return cacheURL
    }
    
    private func modelCacheDirectory() throws -> URL {
        try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MLModels")
    }
    
    private func getLocalModelVersions() -> [String: String] {
        let defaults = UserDefaults.standard
        return defaults.dictionary(forKey: "ModelVersions") as? [String: String] ?? [:]
    }
    
    private func fetchAvailableUpdates() async throws -> [ModelUpdate] {
        var request = URLRequest(url: modelUpdateURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.fetchUpdatesFailed
        }
        
        return try JSONDecoder().decode([ModelUpdate].self, from: data)
    }
    
    private func compareVersions(_ version1: String, isNewerThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<min(v1Components.count, v2Components.count) {
            if v1Components[i] > v2Components[i] {
                return true
            }
            if v1Components[i] < v2Components[i] {
                return false
            }
        }
        
        return v1Components.count > v2Components.count
    }
}

public struct ModelUpdate: Codable {
    public let name: String
    public let version: String
    public let size: Int64
    public let description: String
    public let requiredVersion: String
    public let updatePriority: UpdatePriority
}

public enum UpdatePriority: String, Codable {
    case critical
    case recommended
    case optional
}

public enum ModelError: Error {
    case downloadFailed
    case fetchUpdatesFailed
    case incompatibleVersion
    case invalidCache
}