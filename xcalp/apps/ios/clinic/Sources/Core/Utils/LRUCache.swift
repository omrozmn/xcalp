import Foundation

public final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let key: Key
        let value: Value
        let size: Int
        let timestamp: Date
    }
    
    private var entries: [Key: CacheEntry] = [:]
    private let maxSize: Int
    private let sizeFunction: (Value) -> Int
    private let queue = DispatchQueue(label: "com.xcalp.cache")
    
    public init(maxSize: Int, sizeFunction: @escaping (Value) -> Int) {
        self.maxSize = maxSize
        self.sizeFunction = sizeFunction
    }
    
    public func set(_ value: Value, for key: Key) {
        queue.async {
            let size = self.sizeFunction(value)
            let entry = CacheEntry(
                key: key,
                value: value,
                size: size,
                timestamp: Date()
            )
            
            // Remove oldest entries if needed to make space
            while self.currentSize + size > self.maxSize, let oldestEntry = self.oldestEntry {
                self.entries.removeValue(forKey: oldestEntry.key)
            }
            
            self.entries[key] = entry
        }
    }
    
    public func get(_ key: Key) -> Value? {
        queue.sync {
            guard let entry = entries[key] else { return nil }
            
            // Update timestamp on access
            entries[key] = CacheEntry(
                key: key,
                value: entry.value,
                size: entry.size,
                timestamp: Date()
            )
            
            return entry.value
        }
    }
    
    public func clear() {
        queue.async {
            self.entries.removeAll()
        }
    }
    
    private var currentSize: Int {
        entries.values.reduce(0) { $0 + $1.size }
    }
    
    private var oldestEntry: CacheEntry? {
        entries.values.min { $0.timestamp < $1.timestamp }
    }
}