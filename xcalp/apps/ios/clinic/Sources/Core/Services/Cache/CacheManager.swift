import Foundation
import os.log

public enum CacheError: Error {
    case itemTooLarge
    case quotaExceeded
    case invalidData
    case itemNotFound
}

public final class CacheManager {
    public static let shared = CacheManager()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Cache")
    private let fileManager = FileManager.default
    private let memoryCache = NSCache<NSString, CacheItem>()
    private let diskCache = DiskCache()
    private let maxMemoryCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB
    private let maxDiskCacheSize: UInt64 = 500 * 1024 * 1024   // 500MB
    
    private init() {
        memoryCache.totalCostLimit = Int(maxMemoryCacheSize)
        setupCacheCleanup()
    }
    
    public func store(_ data: Data, forKey key: String, inMemory: Bool = true) throws {
        let item = CacheItem(data: data, timestamp: Date())
        
        if inMemory {
            guard UInt64(data.count) <= maxMemoryCacheSize else {
                throw CacheError.itemTooLarge
            }
            memoryCache.setObject(item, forKey: key as NSString, cost: data.count)
        }
        
        try diskCache.store(item, forKey: key)
    }
    
    public func retrieve(_ key: String) throws -> Data {
        if let item = memoryCache.object(forKey: key as NSString) {
            return item.data
        }
        
        let item = try diskCache.retrieve(key)
        memoryCache.setObject(item, forKey: key as NSString, cost: item.data.count)
        return item.data
    }
    
    public func remove(_ key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        try? diskCache.remove(key)
    }
    
    public func clear() {
        memoryCache.removeAllObjects()
        try? diskCache.clear()
    }
    
    private func setupCacheCleanup() {
        // Cleanup old cache items periodically
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(3600 * 1_000_000_000)) // Every hour
                await cleanup()
            }
        }
    }
    
    @MainActor
    private func cleanup() {
        do {
            try diskCache.cleanup()
            logger.info("Cache cleanup completed successfully")
        } catch {
            logger.error("Cache cleanup failed: \(error.localizedDescription)")
        }
    }
}

private final class CacheItem: NSObject {
    let data: Data
    let timestamp: Date
    
    init(data: Data, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
    }
}

private final class DiskCache {
    private let queue = DispatchQueue(label: "com.xcalp.clinic.diskcache")
    private let cachePath: URL
    private let maxAge: TimeInterval = 7 * 24 * 3600 // 1 week
    
    init() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cachePath = cacheURL.appendingPathComponent("XcalpCache")
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
    }
    
    func store(_ item: CacheItem, forKey key: String) throws {
        let fileURL = cachePath.appendingPathComponent(key)
        try item.data.write(to: fileURL)
    }
    
    func retrieve(_ key: String) throws -> CacheItem {
        let fileURL = cachePath.appendingPathComponent(key)
        let data = try Data(contentsOf: fileURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let timestamp = attributes[.creationDate] as? Date ?? Date()
        return CacheItem(data: data, timestamp: timestamp)
    }
    
    func remove(_ key: String) throws {
        let fileURL = cachePath.appendingPathComponent(key)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    func clear() throws {
        try FileManager.default.removeItem(at: cachePath)
        try FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
    }
    
    func cleanup() throws {
        let contents = try FileManager.default.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: [.creationDateKey])
        let expiredFiles = contents.filter { url in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let creationDate = attributes[.creationDate] as? Date else {
                return true
            }
            return Date().timeIntervalSince(creationDate) > maxAge
        }
        
        for fileURL in expiredFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}