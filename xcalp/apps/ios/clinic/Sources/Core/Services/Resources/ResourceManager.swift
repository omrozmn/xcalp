import Foundation
import os.log

public enum ResourceError: Error, LocalizedError {
    case quotaExceeded(resource: String, limit: UInt64, current: UInt64)
    case resourceUnavailable(resource: String)
    case measurementFailed(resource: String)
    
    public var errorDescription: String? {
        switch self {
        case let .quotaExceeded(resource, limit, current):
            return "\(resource) quota exceeded: \(current)/\(limit)"
        case let .resourceUnavailable(resource):
            return "\(resource) is currently unavailable"
        case let .measurementFailed(resource):
            return "Failed to measure \(resource)"
        }
    }
}

public struct ResourceQuota {
    public let maxMemory: UInt64
    public let maxStorage: UInt64
    public let maxConcurrentTasks: Int
    public let maxBandwidth: UInt64
    
    public init(
        maxMemory: UInt64,
        maxStorage: UInt64,
        maxConcurrentTasks: Int,
        maxBandwidth: UInt64
    ) {
        self.maxMemory = maxMemory
        self.maxStorage = maxStorage
        self.maxConcurrentTasks = maxConcurrentTasks
        self.maxBandwidth = maxBandwidth
    }
}

public struct ResourceUsage {
    public var currentMemory: UInt64
    public var currentStorage: UInt64
    public var currentTasks: Int
    public var currentBandwidth: UInt64
    public var timestamp: Date
    
    public init(
        currentMemory: UInt64,
        currentStorage: UInt64,
        currentTasks: Int,
        currentBandwidth: UInt64,
        timestamp: Date = Date()
    ) {
        self.currentMemory = currentMemory
        self.currentStorage = currentStorage
        self.currentTasks = currentTasks
        self.currentBandwidth = currentBandwidth
        self.timestamp = timestamp
    }
}

@MainActor
public final class ResourceManager {
    public static let shared = ResourceManager()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Resources")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.resources", qos: .userInitiated)
    private let lock = NSLock()
    private let quota: ResourceQuota
    private var usage: ResourceUsage
    private var usageHistory: [ResourceUsage] = []
    private let historyLimit = 100
    private var cleanupTimer: Timer?
    private let cleanupInterval: TimeInterval = 30 // 30 seconds
    
    private init() {
        // Default quotas from blueprint
        self.quota = ResourceQuota(
            maxMemory: 512 * 1024 * 1024,     // 512MB
            maxStorage: 1024 * 1024 * 1024,    // 1GB
            maxConcurrentTasks: 5,
            maxBandwidth: 10 * 1024 * 1024     // 10MB/s
        )
        
        self.usage = ResourceUsage(
            currentMemory: 0,
            currentStorage: 0,
            currentTasks: 0,
            currentBandwidth: 0
        )
        
        setupCleanupTimer()
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            self?.performAutoCleanup()
        }
    }
    
    private func performAutoCleanup() {
        lock.lock()
        defer { lock.unlock() }
        
        let currentTime = Date()
        
        // Clean up expired tasks (older than 5 minutes)
        let expiredTaskCount = usageHistory.filter { 
            currentTime.timeIntervalSince($0.timestamp) > 300 
        }.count
        
        if expiredTaskCount > 0 {
            usage.currentTasks = max(0, usage.currentTasks - expiredTaskCount)
        }
        
        // Reset bandwidth counter every minute
        if let lastUsage = usageHistory.last,
           currentTime.timeIntervalSince(lastUsage.timestamp) > 60 {
            usage.currentBandwidth = 0
        }
        
        // Trim history
        if usageHistory.count > historyLimit {
            usageHistory.removeFirst(usageHistory.count - historyLimit)
        }
        
        // Log current resource state
        logger.debug("Resource state - Memory: \(usage.currentMemory), Tasks: \(usage.currentTasks), Bandwidth: \(usage.currentBandwidth)")
    }
    
    /// Request resources for a task with automatic retry
    /// - Parameters:
    ///   - memory: Required memory in bytes
    ///   - storage: Required storage in bytes
    ///   - bandwidth: Required bandwidth in bytes/s
    ///   - retries: Number of retries if resources unavailable
    ///   - timeout: Timeout for each retry attempt
    public func requestResourcesWithRetry(
        memory: UInt64,
        storage: UInt64,
        bandwidth: UInt64,
        retries: Int = 3,
        timeout: TimeInterval = 5.0
    ) async throws {
        var attempts = 0
        var lastError: Error?
        
        while attempts < retries {
            do {
                try await withTimeout(timeout) {
                    try await self.requestResources(
                        memory: memory,
                        storage: storage,
                        bandwidth: bandwidth
                    )
                }
                return
            } catch let error as ResourceError {
                lastError = error
                attempts += 1
                
                if attempts < retries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts))) * NSEC_PER_SEC)
                }
            }
        }
        
        throw lastError ?? ResourceError.resourceUnavailable(resource: "Unknown")
    }
    
    /// Request resources for a task
    public func requestResources(
        memory: UInt64,
        storage: UInt64,
        bandwidth: UInt64
    ) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        // Verify resources are within quotas
        try verifyQuota(memory: memory, storage: storage, bandwidth: bandwidth)
        
        // Allocate resources
        usage.currentMemory += memory
        usage.currentStorage += storage
        usage.currentBandwidth += bandwidth
        usage.currentTasks += 1
        usage.timestamp = Date()
        
        // Update history
        updateHistory()
        
        logger.info("Resources allocated: Memory=\(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)), Storage=\(ByteCountFormatter.string(fromByteCount: Int64(storage), countStyle: .memory)), Bandwidth=\(bandwidth / 1024 / 1024)MB/s")
        
        // Schedule cleanup if needed
        if usage.currentMemory > quota.maxMemory * 80 / 100 {  // 80% threshold
            Task { @MainActor in
                await cleanupUnusedResources()
            }
        }
    }
    
    private func verifyQuota(memory: UInt64, storage: UInt64, bandwidth: UInt64) throws {
        // Check memory quota
        if usage.currentMemory + memory > quota.maxMemory {
            throw ResourceError.quotaExceeded(
                resource: "Memory",
                limit: quota.maxMemory,
                current: usage.currentMemory
            )
        }
        
        // Check storage quota
        if usage.currentStorage + storage > quota.maxStorage {
            throw ResourceError.quotaExceeded(
                resource: "Storage",
                limit: quota.maxStorage,
                current: usage.currentStorage
            )
        }
        
        // Check bandwidth quota
        if usage.currentBandwidth + bandwidth > quota.maxBandwidth {
            throw ResourceError.quotaExceeded(
                resource: "Bandwidth",
                limit: quota.maxBandwidth,
                current: usage.currentBandwidth
            )
        }
        
        // Check task quota
        if usage.currentTasks + 1 > quota.maxConcurrentTasks {
            throw ResourceError.quotaExceeded(
                resource: "Tasks",
                limit: UInt64(quota.maxConcurrentTasks),
                current: UInt64(usage.currentTasks)
            )
        }
    }
    
    private func updateHistory() {
        usageHistory.append(usage)
        if usageHistory.count > historyLimit {
            usageHistory.removeFirst()
        }
    }
    
    /// Release resources after task completion
    public func releaseResources(
        memory: UInt64,
        storage: UInt64,
        bandwidth: UInt64
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        usage.currentMemory = usage.currentMemory > memory ? usage.currentMemory - memory : 0
        usage.currentStorage = usage.currentStorage > storage ? usage.currentStorage - storage : 0
        usage.currentBandwidth = usage.currentBandwidth > bandwidth ? usage.currentBandwidth - bandwidth : 0
        usage.currentTasks = usage.currentTasks > 0 ? usage.currentTasks - 1 : 0
        usage.timestamp = Date()
        
        updateHistory()
        
        logger.info("Resources released: Memory=\(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)), Storage=\(ByteCountFormatter.string(fromByteCount: Int64(storage), countStyle: .memory)), Bandwidth=\(bandwidth / 1024 / 1024)MB/s")
    }
    
    /// Clean up unused resources
    private func cleanupUnusedResources() async {
        lock.lock()
        defer { lock.unlock() }
        
        // Cleanup temporary files
        do {
            let tempURL = FileManager.default.temporaryDirectory
            let tempContents = try FileManager.default.contentsOfDirectory(
                at: tempURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
            )
            
            let oldFiles = tempContents.filter { url in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return Date().timeIntervalSince(date) > 3600 // Older than 1 hour
            }
            
            var freedStorage: UInt64 = 0
            for file in oldFiles {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    freedStorage += UInt64(size)
                }
                try FileManager.default.removeItem(at: file)
            }
            
            if freedStorage > 0 {
                usage.currentStorage -= min(usage.currentStorage, freedStorage)
                logger.info("Cleaned up \(ByteCountFormatter.string(fromByteCount: Int64(freedStorage), countStyle: .memory)) of temporary files")
            }
        } catch {
            logger.error("Failed to cleanup temporary files: \(error.localizedDescription)")
        }
        
        // Reset bandwidth counter if no recent activity
        if let lastUsage = usageHistory.last,
           Date().timeIntervalSince(lastUsage.timestamp) > 60 {
            usage.currentBandwidth = 0
        }
        
        updateHistory()
    }
    
    /// Get current resource usage
    public var currentUsage: ResourceUsage {
        lock.lock()
        defer { lock.unlock() }
        return usage
    }
    
    /// Get resource usage history
    public var resourceHistory: [ResourceUsage] {
        lock.lock()
        defer { lock.unlock() }
        return usageHistory
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - Dependency Interface

public struct ResourceClient {
    public var requestResources: (UInt64, UInt64, UInt64) throws -> Void
    public var releaseResources: (UInt64, UInt64, UInt64) -> Void
    public var currentUsage: () -> ResourceUsage
    public var quotaLimits: () -> ResourceQuota
    public var resourceHistory: () -> [ResourceUsage]
    
    public init(
        requestResources: @escaping (UInt64, UInt64, UInt64) throws -> Void,
        releaseResources: @escaping (UInt64, UInt64, UInt64) -> Void,
        currentUsage: @escaping () -> ResourceUsage,
        quotaLimits: @escaping () -> ResourceQuota,
        resourceHistory: @escaping () -> [ResourceUsage]
    ) {
        self.requestResources = requestResources
        self.releaseResources = releaseResources
        self.currentUsage = currentUsage
        self.quotaLimits = quotaLimits
        self.resourceHistory = resourceHistory
    }
}

extension ResourceClient {
    public static let live = Self(
        requestResources: { try ResourceManager.shared.requestResources(memory: $0, storage: $1, bandwidth: $2) },
        releaseResources: { ResourceManager.shared.releaseResources(memory: $0, storage: $1, bandwidth: $2) },
        currentUsage: { ResourceManager.shared.currentUsage },
        quotaLimits: { ResourceManager.shared.quotaLimits },
        resourceHistory: { ResourceManager.shared.resourceHistory }
    )
    
    public static let test = Self(
        requestResources: { _, _, _ in },
        releaseResources: { _, _, _ in },
        currentUsage: {
            ResourceUsage(
                currentMemory: 0,
                currentStorage: 0,
                currentTasks: 0,
                currentBandwidth: 0
            )
        },
        quotaLimits: {
            ResourceQuota(
                maxMemory: UInt64.max,
                maxStorage: UInt64.max,
                maxConcurrentTasks: Int.max,
                maxBandwidth: UInt64.max
            )
        },
        resourceHistory: { [] }
    )
}
