import Foundation
import UIKit

public actor BackgroundTaskManager {
    public static let shared = BackgroundTaskManager()
    
    private let analytics: AnalyticsService
    private let performanceMonitor: PerformanceMonitor
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "BackgroundTasks")
    
    private var activeTasks: [UUID: BackgroundTask] = [:]
    private var scheduledTasks: [UUID: ScheduledTask] = [:]
    private var taskHistory: [TaskRecord] = []
    
    private let maxConcurrentTasks = 3
    private let historyLimit = 100
    
    private init(
        analytics: AnalyticsService = .shared,
        performanceMonitor: PerformanceMonitor = .shared
    ) {
        self.analytics = analytics
        self.performanceMonitor = performanceMonitor
        setupBackgroundHandling()
    }
    
    public func startTask(
        name: String,
        priority: TaskPriority = .default,
        isEssential: Bool = false
    ) async throws -> UUID {
        // Check system resources
        let metrics = performanceMonitor.reportResourceMetrics()
        guard canStartNewTask(metrics) else {
            throw BackgroundError.resourceConstraint
        }
        
        // Create and register task
        let task = BackgroundTask(
            id: UUID(),
            name: name,
            priority: priority,
            isEssential: isEssential,
            startTime: Date()
        )
        
        // Register with iOS background task system
        let backgroundTaskID = await registerWithSystem(task)
        
        // Store task
        activeTasks[task.id] = task
        
        // Track task start
        analytics.track(
            event: .backgroundTaskStarted,
            properties: [
                "taskId": task.id.uuidString,
                "name": name,
                "priority": priority.rawValue
            ]
        )
        
        logger.info("Started background task: \(name)")
        return task.id
    }
    
    public func scheduleTask(
        name: String,
        execution: @escaping () async throws -> Void,
        priority: TaskPriority = .default,
        isEssential: Bool = false,
        deadline: Date
    ) async throws -> UUID {
        let scheduledTask = ScheduledTask(
            id: UUID(),
            name: name,
            execution: execution,
            priority: priority,
            isEssential: isEssential,
            deadline: deadline
        )
        
        scheduledTasks[scheduledTask.id] = scheduledTask
        
        // Schedule execution
        Task {
            await scheduleExecution(scheduledTask)
        }
        
        return scheduledTask.id
    }
    
    public func endTask(_ taskId: UUID) async {
        guard let task = activeTasks[taskId] else { return }
        
        // End iOS background task
        await endSystemTask(task)
        
        // Record task completion
        let record = TaskRecord(
            id: task.id,
            name: task.name,
            startTime: task.startTime,
            endTime: Date(),
            status: .completed
        )
        
        recordTaskHistory(record)
        
        // Remove from active tasks
        activeTasks.removeValue(forKey: taskId)
        
        // Track completion
        analytics.track(
            event: .backgroundTaskCompleted,
            properties: [
                "taskId": taskId.uuidString,
                "name": task.name,
                "duration": record.duration
            ]
        )
        
        logger.info("Completed background task: \(task.name)")
    }
    
    public func pauseNonEssentialTasks() async {
        for task in activeTasks.values where !task.isEssential {
            await pauseTask(task.id)
        }
    }
    
    public func stopAllTasks() async {
        for taskId in activeTasks.keys {
            await endTask(taskId)
        }
        
        scheduledTasks.removeAll()
    }
    
    private func pauseTask(_ taskId: UUID) async {
        guard let task = activeTasks[taskId] else { return }
        
        // Record pause
        let record = TaskRecord(
            id: task.id,
            name: task.name,
            startTime: task.startTime,
            endTime: Date(),
            status: .paused
        )
        
        recordTaskHistory(record)
        
        // Track pause
        analytics.track(
            event: .backgroundTaskPaused,
            properties: [
                "taskId": taskId.uuidString,
                "name": task.name
            ]
        )
    }
    
    private func canStartNewTask(_ metrics: ResourceMetrics) -> Bool {
        // Check active task count
        guard activeTasks.count < maxConcurrentTasks else {
            return false
        }
        
        // Check system resources
        guard metrics.cpuUsage < 0.8 &&
              metrics.memoryUsage < 0.8 &&
              metrics.thermalState != .serious &&
              metrics.thermalState != .critical else {
            return false
        }
        
        return true
    }
    
    private func scheduleExecution(_ task: ScheduledTask) async {
        let interval = task.deadline.timeIntervalSince(Date())
        if interval > 0 {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        
        do {
            try await startTask(
                name: task.name,
                priority: task.priority,
                isEssential: task.isEssential
            )
            try await task.execution()
        } catch {
            logger.error("Failed to execute scheduled task: \(error.localizedDescription)")
            
            analytics.track(
                event: .backgroundTaskFailed,
                properties: [
                    "taskId": task.id.uuidString,
                    "name": task.name,
                    "error": error.localizedDescription
                ]
            )
        }
        
        scheduledTasks.removeValue(forKey: task.id)
    }
    
    private func registerWithSystem(_ task: BackgroundTask) async -> UIBackgroundTaskIdentifier {
        await withUnsafeContinuation { continuation in
            let taskID = UIApplication.shared.beginBackgroundTask(
                withName: task.name
            ) { [weak self] in
                Task { [id = task.id] in
                    await self?.endTask(id)
                }
            }
            continuation.resume(returning: taskID)
        }
    }
    
    private func endSystemTask(_ task: BackgroundTask) async {
        // Implementation for ending system background task
    }
    
    private func recordTaskHistory(_ record: TaskRecord) {
        taskHistory.append(record)
        
        if taskHistory.count > historyLimit {
            taskHistory.removeFirst()
        }
    }
    
    private func setupBackgroundHandling() {
        // Implementation for setting up background handling
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleAppBackground()
            }
        }
    }
    
    private func handleAppBackground() async {
        // Pause non-essential tasks when app enters background
        await pauseNonEssentialTasks()
    }
}

// MARK: - Types

extension BackgroundTaskManager {
    public enum TaskPriority: String {
        case high
        case `default`
        case low
        case background
    }
    
    public enum TaskStatus: String {
        case active
        case completed
        case paused
        case failed
    }
    
    public enum BackgroundError: LocalizedError {
        case resourceConstraint
        case taskNotFound
        case executionFailed
        
        public var errorDescription: String? {
            switch self {
            case .resourceConstraint:
                return "Cannot start new task due to resource constraints"
            case .taskNotFound:
                return "Background task not found"
            case .executionFailed:
                return "Task execution failed"
            }
        }
    }
    
    struct BackgroundTask {
        let id: UUID
        let name: String
        let priority: TaskPriority
        let isEssential: Bool
        let startTime: Date
    }
    
    struct ScheduledTask {
        let id: UUID
        let name: String
        let execution: () async throws -> Void
        let priority: TaskPriority
        let isEssential: Bool
        let deadline: Date
    }
    
    struct TaskRecord {
        let id: UUID
        let name: String
        let startTime: Date
        let endTime: Date
        let status: TaskStatus
        
        var duration: TimeInterval {
            endTime.timeIntervalSince(startTime)
        }
    }
}

extension AnalyticsService.Event {
    static let backgroundTaskStarted = AnalyticsService.Event(name: "background_task_started")
    static let backgroundTaskCompleted = AnalyticsService.Event(name: "background_task_completed")
    static let backgroundTaskPaused = AnalyticsService.Event(name: "background_task_paused")
    static let backgroundTaskFailed = AnalyticsService.Event(name: "background_task_failed")
}