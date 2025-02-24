import Foundation

public protocol NetworkCache {
    func cache<T: Encodable>(_ item: T, for key: String) throws
    func retrieve<T: Decodable>(for key: String) throws -> T
    func remove(for key: String) throws
    func clear() throws
    var isEnabled: Bool { get set }
}

public final class NetworkCacheImpl: NetworkCache {
    private let storage: CacheStorage
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxAge: TimeInterval
    public var isEnabled: Bool
    
    public init(
        storage: CacheStorage = FileBasedCacheStorage(),
        maxAge: TimeInterval = 3600, // 1 hour default
        isEnabled: Bool = true
    ) {
        self.storage = storage
        self.maxAge = maxAge
        self.isEnabled = isEnabled
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    public func cache<T: Encodable>(_ item: T, for key: String) throws {
        guard isEnabled else { return }
        
        let wrapper = CacheEntry(
            timestamp: Date(),
            maxAge: maxAge,
            data: try encoder.encode(item)
        )
        
        try storage.store(try encoder.encode(wrapper), for: key)
    }
    
    public func retrieve<T: Decodable>(for key: String) throws -> T {
        guard isEnabled else { throw CacheError.disabled }
        
        let data = try storage.retrieve(for: key)
        let wrapper = try decoder.decode(CacheEntry.self, from: data)
        
        guard !wrapper.isExpired else {
            try? remove(for: key)
            throw CacheError.expired
        }
        
        return try decoder.decode(T.self, from: wrapper.data)
    }
    
    public func remove(for key: String) throws {
        try storage.remove(for: key)
    }
    
    public func clear() throws {
        try storage.clear()
    }
}

// MARK: - Supporting Types

private struct CacheEntry: Codable {
    let timestamp: Date
    let maxAge: TimeInterval
    let data: Data
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > maxAge
    }
}

public enum CacheError: Error {
    case disabled
    case expired
    case invalidData
    case storageError(Error)
}

public protocol CacheStorage {
    func store(_ data: Data, for key: String) throws
    func retrieve(for key: String) throws -> Data
    func remove(for key: String) throws
    func clear() throws
}

public final class FileBasedCacheStorage: CacheStorage {
    private let fileManager: FileManager
    private let cacheDirectory: URL
    
    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        
        let cacheDir = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        self.cacheDirectory = cacheDir.appendingPathComponent("NetworkCache", isDirectory: true)
        
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    public func store(_ data: Data, for key: String) throws {
        let fileURL = cacheDirectory.appendingPathComponent(key.md5)
        try data.write(to: fileURL, options: .atomic)
    }
    
    public func retrieve(for key: String) throws -> Data {
        let fileURL = cacheDirectory.appendingPathComponent(key.md5)
        return try Data(contentsOf: fileURL)
    }
    
    public func remove(for key: String) throws {
        let fileURL = cacheDirectory.appendingPathComponent(key.md5)
        try fileManager.removeItem(at: fileURL)
    }
    
    public func clear() throws {
        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        
        try contents.forEach { url in
            try fileManager.removeItem(at: url)
        }
    }
}

// MARK: - Extensions

private extension String {
    var md5: String {
        let length = Int(CC_MD5_DIGEST_LENGTH)
        var digest = [UInt8](repeating: 0, count: length)
        
        if let data = data(using: .utf8) {
            _ = data.withUnsafeBytes { buffer in
                CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
            }
        }
        
        return digest.reduce("") { $0 + String(format: "%02x", $1) }
    }
}
