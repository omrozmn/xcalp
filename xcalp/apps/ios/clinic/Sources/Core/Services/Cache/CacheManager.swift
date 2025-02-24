import Foundation
import os.log

public enum CacheError: Error {
    case itemTooLarge
    case quotaExceeded
    case invalidData
    case itemNotFound
    case priorityTooLow
}

public enum CachePriority: Int {
    case low = 0
    case medium = 1
    case high = 2
    
    var maxAge: TimeInterval {
        switch self {
        case .low: return 24 * 3600 // 1 day
        case .medium: return 3 * 24 * 3600 // 3 days
        case .high: return 7 * 24 * 3600 // 7 days
        }
    }
}

public final class CacheManager {
    public static let shared = CacheManager()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Cache")
    private let fileManager = FileManager.default
    private let memoryCache = NSCache<NSString, CacheItem>()
    private let diskCache = DiskCache()
    private let maxMemoryCacheSize: UInt64 = 50 * 1024 * 1024  // 50MB
    private let maxDiskCacheSize: UInt64 = 500 * 1024 * 1024   // 500MB
    private let minAvailableSpace: UInt64 = 100 * 1024 * 1024  // 100MB
    
    private var cacheStats: CacheStats = CacheStats()
    private var currentDiskUsage: UInt64 = 0
    private var itemRegistry: [String: CacheItemMetadata] = [:]
    private let queue = DispatchQueue(label: "com.xcalp.clinic.cache", qos: .utility)
    
    private init() {
        memoryCache.totalCostLimit = Int(maxMemoryCacheSize)
        setupCacheCleanup()
        loadItemRegistry()
    }
    
    public func store(_ data: Data, forKey key: String, priority: CachePriority = .medium, inMemory: Bool = true) async throws {
        let item = CacheItem(data: data, timestamp: Date(), priority: priority)
        
        // Check size constraints
        if inMemory && UInt64(data.count) > maxMemoryCacheSize {
            throw CacheError.itemTooLarge
        }
        
        // Check available disk space
        let availableSpace = try getAvailableDiskSpace()
        if availableSpace < minAvailableSpace {
            await performEmergencyCleanup()
        }
        
        // Update stats and registry
        await updateCacheStats(forOperation: .write, size: UInt64(data.count))
        
        let metadata = CacheItemMetadata(
            key: key,
            size: UInt64(data.count),
            priority: priority,
            lastAccessed: Date(),
            hitCount: 0
        )
        
        try await queue.async {
            self.itemRegistry[key] = metadata
            
            if inMemory {
                self.memoryCache.setObject(item, forKey: key as NSString, cost: data.count)
            }
            
            try self.diskCache.store(item, forKey: key)
            self.currentDiskUsage += UInt64(data.count)
            
            try self.saveItemRegistry()
        }
    }
    
    public func retrieve(_ key: String) async throws -> Data {
        // Update access statistics
        if var metadata = itemRegistry[key] {
            metadata.lastAccessed = Date()
            metadata.hitCount += 1
            itemRegistry[key] = metadata
            try await queue.async { try self.saveItemRegistry() }
        }
        
        // Try memory cache first
        if let item = memoryCache.object(forKey: key as NSString) {
            await updateCacheStats(forOperation: .hit, size: UInt64(item.data.count))
            return item.data
        }
        
        // Try disk cache
        let item = try await queue.async { try self.diskCache.retrieve(key) }
        
        // Update stats
        await updateCacheStats(forOperation: .miss, size: UInt64(item.data.count))
        
        // Add to memory cache if not expired
        if Date().timeIntervalSince(item.timestamp) <= item.priority.maxAge {
            memoryCache.setObject(item, forKey: key as NSString, cost: item.data.count)
        }
        
        return item.data
    }
    
    private func loadItemRegistry() {
        let registryURL = diskCache.cachePath.appendingPathComponent("registry.json")
        do {
            let data = try Data(contentsOf: registryURL)
            itemRegistry = try JSONDecoder().decode([String: CacheItemMetadata].self, from: data)
        } catch {
            logger.error("Failed to load cache registry: \(error.localizedDescription)")
            itemRegistry = [:]
        }
    }
    
    private func saveItemRegistry() throws {
        let registryURL = diskCache.cachePath.appendingPathComponent("registry.json")
        let data = try JSONEncoder().encode(itemRegistry)
        try data.write(to: registryURL)
    }
    
    private func getAvailableDiskSpace() throws -> UInt64 {
        let url = diskCache.cachePath
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else {
            throw CacheError.invalidData
        }
        return UInt64(capacity)
    }
    
    @MainActor
    private func performEmergencyCleanup() async {
        logger.warning("Performing emergency cache cleanup")
        
        // Remove expired items first
        await cleanupExpiredItems()
        
        // If still need space, remove low priority items
        if try? getAvailableDiskSpace() < minAvailableSpace {
            await cleanupByPriority(.low)
        }
        
        // If still need space, remove least accessed items
        if try? getAvailableDiskSpace() < minAvailableSpace {
            await cleanupLeastAccessed()
        }
    }
    
    @MainActor
    private func cleanupExpiredItems() async {
        let now = Date()
        var itemsToRemove: [String] = []
        
        for (key, metadata) in itemRegistry {
            if now.timeIntervalSince(metadata.lastAccessed) > metadata.priority.maxAge {
                itemsToRemove.append(key)
            }
        }
        
        for key in itemsToRemove {
            try? await remove(key)
        }
    }
    
    @MainActor
    private func cleanupByPriority(_ maxPriority: CachePriority) async {
        let itemsToRemove = itemRegistry.filter { $0.value.priority.rawValue <= maxPriority.rawValue }
        for key in itemsToRemove.keys {
            try? await remove(key)
        }
    }
    
    @MainActor
    private func cleanupLeastAccessed() async {
        let sortedItems = itemRegistry.sorted { $0.value.hitCount < $1.value.hitCount }
        let itemsToRemove = sortedItems.prefix(sortedItems.count / 2)
        for item in itemsToRemove {
            try? await remove(item.key)
        }
    }
    
    public func remove(_ key: String) async throws {
        try await queue.async {
            if let metadata = self.itemRegistry[key] {
                self.currentDiskUsage -= metadata.size
            }
            
            self.memoryCache.removeObject(forKey: key as NSString)
            try self.diskCache.remove(key)
            self.itemRegistry.removeValue(forKey: key)
            try self.saveItemRegistry()
        }
    }
    
    @MainActor
    private func updateCacheStats(forOperation operation: CacheOperation, size: UInt64) {
        switch operation {
        case .hit:
            cacheStats.hits += 1
            cacheStats.bytesRead += size
        case .miss:
            cacheStats.misses += 1
            cacheStats.bytesRead += size
        case .write:
            cacheStats.writes += 1
            cacheStats.bytesWritten += size
        }
    }
}

private struct CacheItemMetadata: Codable {
    let key: String
    let size: UInt64
    let priority: CachePriority
    var lastAccessed: Date
    var hitCount: Int
}

private enum CacheOperation {
    case hit, miss, write
}

private struct CacheStats {
    var hits: Int = 0
    var misses: Int = 0
    var writes: Int = 0
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    
    var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0
    }
}

private final class CacheItem: NSObject {
    let data: Data
    let timestamp: Date
    let priority: CachePriority
    
    init(data: Data, timestamp: Date, priority: CachePriority) {
        self.data = data
        self.timestamp = timestamp
        self.priority = priority
        super.init()
    }
}

private final class DiskCache {
    private let queue = DispatchQueue(label: "com.xcalp.clinic.diskcache")
    let cachePath: URL
    private let maxAge: TimeInterval = 7 * 24 * 3600 // 1 week
    
    init() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cachePath = cacheURL.appendingPathComponent("XcalpCache")
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
        setupDirectoryProtection()
    }
    
    private func setupDirectoryProtection() {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: cachePath.path
        )
    }
    
    func store(_ item: CacheItem, forKey key: String) throws {
        let fileURL = cachePath.appendingPathComponent(key)
        
        // Create a container with metadata
        let container = CacheContainer(
            data: item.data,
            timestamp: item.timestamp,
            priority: item.priority
        )
        
        let encoder = PropertyListEncoder()
        let data = try encoder.encode(container)
        try data.write(to: fileURL, options: .completeFileProtection)
    }
    
    func retrieve(_ key: String) throws -> CacheItem {
        let fileURL = cachePath.appendingPathComponent(key)
        let data = try Data(contentsOf: fileURL)
        
        let decoder = PropertyListDecoder()
        let container = try decoder.decode(CacheContainer.self, from: data)
        
        return CacheItem(
            data: container.data,
            timestamp: container.timestamp,
            priority: container.priority
        )
    }
    
    func remove(_ key: String) throws {
        let fileURL = cachePath.appendingPathComponent(key)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    func clear() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: cachePath,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func cleanup() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: cachePath,
            includingPropertiesForKeys: [.creationDateKey]
        )
        
        for url in contents {
            guard url.lastPathComponent != "registry.json" else { continue }
            
            do {
                let data = try Data(contentsOf: url)
                let decoder = PropertyListDecoder()
                let container = try decoder.decode(CacheContainer.self, from: data)
                
                if Date().timeIntervalSince(container.timestamp) > container.priority.maxAge {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {
                // If we can't read the file, remove it
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

private struct CacheContainer: Codable {
    let data: Data
    let timestamp: Date
    let priority: CachePriority
}
