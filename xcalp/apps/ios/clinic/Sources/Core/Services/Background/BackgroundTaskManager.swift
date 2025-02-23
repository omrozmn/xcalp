import Foundation
import UIKit
import os.log

public enum BackgroundTaskError: Error, LocalizedError {
    case taskExpired
    case invalidIdentifier
    case taskLimitExceeded
    case alreadyRunning
    case taskQueued
    
    public var errorDescription: String? {
        switch self {
        case .taskExpired:
            return "Background task expired before completion"
        case .invalidIdentifier:
            return "Invalid background task identifier"
        case .taskLimitExceeded:
            return "Maximum number of background tasks exceeded"
        case .alreadyRunning:
            return "Task is already running"
        case .taskQueued:
            return "Task has been queued due to resource constraints"
        }
    }
}

public enum TaskPriority: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TaskResources {
    public let memory: UInt64
    public let storage: UInt64
    public let bandwidth: UInt64
    
    public init(memory: UInt64, storage: UInt64, bandwidth: UInt64) {
        self.memory = memory
        self.storage = storage
        self.bandwidth = bandwidth
    }
}

@MainActor
public final class BackgroundTaskManager: ObservableObject {
    public static let shared = BackgroundTaskManager()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Background")
    private let taskTimeout: TimeInterval = 180 // 3 minutes
    private let maxConcurrentTasks = 5
    private let taskPriorityQueue = PriorityQueue<String>()
    private let resourceCheckInterval: TimeInterval = 10 // 10 seconds
    
    @Published private(set) var activeTasks: [String: BackgroundTask] = [:]
    @Published private(set) var isProcessing: Bool = false
    
    @Dependency(\.resourceClient) var resourceClient
    
    private init() {
        setupResourceMonitoring()
    }
    
    private func setupResourceMonitoring() {
        // Monitor resources periodically
        Task {
            while true {
                await checkAndOptimizeResources()
                try? await Task.sleep(nanoseconds: UInt64(resourceCheckInterval * 1_000_000_000))
            }
        }
    }
    
    private func checkAndOptimizeResources() async {
        let usage = resourceClient.currentUsage()
        let quota = resourceClient.quotaLimits()
        
        // Check memory pressure
        if usage.currentMemory > quota.maxMemory * 80 / 100 {
            // High memory usage - suspend low priority tasks
            for taskId in tasks(withPriority: .low) {
                await suspendTask(taskId)
            }
        }
        
        // Resume suspended tasks if resources available
        if usage.currentMemory < quota.maxMemory * 60 / 100 {
            await resumeSuspendedTasks()
        }
    }
    
    private func suspendTask(_ identifier: String) async {
        guard let task = activeTasks[identifier] else { return }
        task.status = .suspended
        logger.info("Suspended task due to resource pressure: \(identifier)")
    }
    
    private func resumeSuspendedTasks() async {
        for (identifier, task) in activeTasks where task.status == .suspended {
            task.status = .running
            logger.info("Resumed suspended task: \(identifier)")
        }
    }
    
    /// Start a new background task with a given name and priority
    /// - Parameters:
    ///   - name: Name of the task for identification
    ///   - priority: Priority level of the task
    ///   - resources: Required resources for the task
    ///   - operation: The operation to perform in the background
    /// - Returns: Background task identifier
    public func beginTask(
        name: String,
        priority: TaskPriority = .medium,
        resources: TaskResources,
        operation: @escaping () async throws -> Void
    ) async throws -> String {
        guard activeTasks.count < maxConcurrentTasks else {
            // Queue the task instead of failing
            taskPriorityQueue.enqueue(name, priority: priority.rawValue)
            throw BackgroundTaskError.taskQueued
        }
        
        guard !activeTasks.keys.contains(name) else {
            throw BackgroundTaskError.alreadyRunning
        }
        
        // Request resources
        try resourceClient.requestResources(
            resources.memory,
            resources.storage,
            resources.bandwidth
        )
        
        let task = BackgroundTask(
            name: name,
            priority: priority,
            resources: resources
        )
        activeTasks[name] = task
        isProcessing = true
        
        logger.info("Starting background task: \(name) with priority: \(priority)")
        
        // Start expiration timer
        Task {
            try await Task.sleep(nanoseconds: UInt64(taskTimeout * 1_000_000_000))
            if activeTasks[name] != nil {
                await endTask(name, error: BackgroundTaskError.taskExpired)
            }
        }
        
        // Execute operation
        Task {
            do {
                try await operation()
                await endTask(name)
            } catch {
                await endTask(name, error: error)
            }
        }
        
        return name
    }
    
    /// End a background task
    /// - Parameters:
    ///   - identifier: Task identifier to end
    ///   - error: Optional error if task failed
    public func endTask(_ identifier: String, error: Error? = nil) async {
        guard let task = activeTasks[identifier] else {
            logger.error("Attempted to end non-existent task: \(identifier)")
            return
        }
        
        // Release resources
        resourceClient.releaseResources(
            task.resources.memory,
            task.resources.storage,
            task.resources.bandwidth
        )
        
        activeTasks[identifier] = nil
        isProcessing = !activeTasks.isEmpty
        
        if let error = error {
            logger.error("Background task failed: \(identifier), error: \(error.localizedDescription)")
            task.completion?(.failure(error))
        } else {
            logger.info("Background task completed: \(identifier)")
            task.completion?(.success(()))
        }
        
        // Check queued tasks
        if let nextTask = taskPriorityQueue.dequeue() {
            logger.info("Starting queued task: \(nextTask)")
            // Start the queued task
            if let task = activeTasks[nextTask] {
                task.status = .running
            }
        }
    }
    
    /// Get status of a background task
    /// - Parameter identifier: Task identifier to check
    /// - Returns: Current task status
    public func taskStatus(_ identifier: String) -> BackgroundTaskStatus {
        guard let task = activeTasks[identifier] else {
            return .completed
        }
        return task.status
    }
    
    /// Cancel all running background tasks
    public func cancelAllTasks() async {
        for identifier in activeTasks.keys {
            await endTask(identifier, error: CancellationError())
        }
    }
    
    /// Get all tasks with a specific priority
    /// - Parameter priority: Priority level to filter by
    /// - Returns: Array of task identifiers
    public func tasks(withPriority priority: TaskPriority) -> [String] {
        activeTasks.filter { $0.value.priority == priority }.map { $0.key }
    }
    
    /// Get tasks sorted by priority
    /// - Returns: Array of task identifiers sorted by priority (highest first)
    public func tasksSortedByPriority() -> [String] {
        activeTasks.sorted { $0.value.priority > $1.value.priority }.map { $0.key }
    }
}

private final class BackgroundTask {
    let name: String
    let priority: TaskPriority
    let resources: TaskResources
    var status: BackgroundTaskStatus = .running
    var completion: ((Result<Void, Error>) -> Void)?
    
    init(name: String, priority: TaskPriority, resources: TaskResources) {
        self.name = name
        self.priority = priority
        self.resources = resources
    }
}

public enum BackgroundTaskStatus {
    case running
    case completed
    case failed(Error)
    case suspended
}

public struct BackgroundTaskClient {
    public var beginTask: (String, TaskPriority, TaskResources, @escaping () async throws -> Void) async throws -> String
    public var endTask: (String, Error?) async -> Void
    public var taskStatus: (String) -> BackgroundTaskStatus
    public var cancelAllTasks: () async -> Void
    public var tasksWithPriority: (TaskPriority) -> [String]
    public var tasksSortedByPriority: () -> [String]
    
    public init(
        beginTask: @escaping (String, TaskPriority, TaskResources, @escaping () async throws -> Void) async throws -> String,
        endTask: @escaping (String, Error?) async -> Void,
        taskStatus: @escaping (String) -> BackgroundTaskStatus,
        cancelAllTasks: @escaping () async -> Void,
        tasksWithPriority: @escaping (TaskPriority) -> [String],
        tasksSortedByPriority: @escaping () -> [String]
    ) {
        self.beginTask = beginTask
        self.endTask = endTask
        self.taskStatus = taskStatus
        self.cancelAllTasks = cancelAllTasks
        self.tasksWithPriority = tasksWithPriority
        self.tasksSortedByPriority = tasksSortedByPriority
    }
}

extension BackgroundTaskClient {
    public static let live = Self(
        beginTask: { name, priority, resources, operation in
            try await BackgroundTaskManager.shared.beginTask(name: name, priority: priority, resources: resources, operation: operation)
        },
        endTask: { identifier, error in
            await BackgroundTaskManager.shared.endTask(identifier, error: error)
        },
        taskStatus: { identifier in
            BackgroundTaskManager.shared.taskStatus(identifier)
        },
        cancelAllTasks: {
            await BackgroundTaskManager.shared.cancelAllTasks()
        },
        tasksWithPriority: { priority in
            BackgroundTaskManager.shared.tasks(withPriority: priority)
        },
        tasksSortedByPriority: {
            BackgroundTaskManager.shared.tasksSortedByPriority()
        }
    )
    
    public static let test = Self(
        beginTask: { name, _, _, _ in name },
        endTask: { _, _ in },
        taskStatus: { _ in .completed },
        cancelAllTasks: { },
        tasksWithPriority: { _ in [] },
        tasksSortedByPriority: { [] }
    )
}

private class PriorityQueue<T> {
    private var elements: [(T, Int)] = []
    
    func enqueue(_ element: T, priority: Int) {
        elements.append((element, priority))
        elements.sort { $0.1 > $1.1 }
    }
    
    func dequeue() -> T? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst().0
    }
}
