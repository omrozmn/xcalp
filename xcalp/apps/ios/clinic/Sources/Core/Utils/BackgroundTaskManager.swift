import Foundation
import os.log
import UIKit

public final class BackgroundTaskManager {
    public static let shared = BackgroundTaskManager()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "BackgroundTask")
    private let queue = DispatchQueue(label: "com.xcalp.clinic.backgroundtask")
    
    private var activeTasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var taskStartTimes: [String: Date] = [:]
    private let maxTaskDuration: TimeInterval = 180 // 3 minutes
    
    private init() {}
    
    @discardableResult
    public func beginTask(_ name: String) async -> String {
        let taskID = UUID().uuidString
        let fullTaskName = "\(name)_\(taskID)"
        
        await withCheckedContinuation { continuation in
            queue.async {
                let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: fullTaskName) { [weak self] in
                    self?.handleTaskExpiration(taskID: taskID)
                }
                
                if backgroundTask != .invalid {
                    self.activeTasks[taskID] = backgroundTask
                    self.taskStartTimes[taskID] = Date()
                    
                    self.logger.info("Started background task: \(fullTaskName)")
                } else {
                    self.logger.error("Failed to start background task: \(fullTaskName)")
                }
                
                continuation.resume()
            }
        }
        
        // Start monitoring task duration
        Task {
            try await monitorTaskDuration(taskID)
        }
        
        return taskID
    }
    
    public func endTask(_ taskID: String) {
        queue.async { [weak self] in
            guard let self = self,
                  let backgroundTask = self.activeTasks[taskID] else {
                return
            }
            
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self.activeTasks.removeValue(forKey: taskID)
            self.taskStartTimes.removeValue(forKey: taskID)
            
            self.logger.info("Ended background task: \(taskID)")
        }
    }
    
    private func handleTaskExpiration(taskID: String) {
        queue.async { [weak self] in
            guard let self = self,
                  let backgroundTask = self.activeTasks[taskID] else {
                return
            }
            
            self.logger.warning("Background task expired: \(taskID)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self.activeTasks.removeValue(forKey: taskID)
            self.taskStartTimes.removeValue(forKey: taskID)
        }
    }
    
    private func monitorTaskDuration(_ taskID: String) async throws {
        while true {
            guard let startTime = taskStartTimes[taskID] else {
                return
            }
            
            let duration = Date().timeIntervalSince(startTime)
            if duration >= maxTaskDuration {
                logger.warning("Background task \(taskID) approaching time limit")
                endTask(taskID)
                return
            }
            
            try await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
        }
    }
    
    public func endAllTasks() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            for (taskID, backgroundTask) in self.activeTasks {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                self.logger.info("Ended background task: \(taskID)")
            }
            
            self.activeTasks.removeAll()
            self.taskStartTimes.removeAll()
        }
    }
}
