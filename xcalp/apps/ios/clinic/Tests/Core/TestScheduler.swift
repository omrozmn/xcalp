import Foundation
import Metal
import XCTest
@testable import xcalp

final class TestScheduler {
    private let resourceManager: ResourceManager
    private let testQueue: OperationQueue
    private let device: MTLDevice
    private var scheduledTests: [ScheduledTest] = []
    private var runningTests: [UUID: TestExecution] = [:]
    
    struct ScheduledTest {
        let id: UUID
        let test: XCTestCase
        let priority: Priority
        let resourceRequirements: ResourceRequirements
        let dependencies: Set<UUID>
        let timeout: TimeInterval
        
        enum Priority: Int {
            case low = 0
            case normal = 1
            case high = 2
            case critical = 3
        }
    }
    
    struct ResourceRequirements {
        let cpuCores: Int
        let memoryMB: UInt64
        let gpuMemoryMB: UInt64
        let expectedDuration: TimeInterval
    }
    
    struct TestExecution {
        let test: ScheduledTest
        let startTime: Date
        let assignedResources: AssignedResources
        var status: ExecutionStatus
        
        enum ExecutionStatus {
            case queued
            case running
            case completed(Result<Void, Error>)
            case timeout
        }
    }
    
    struct AssignedResources {
        let cpuCores: [Int]
        let memoryRange: Range<UInt64>
        let gpuMemoryRange: Range<UInt64>
    }
    
    init(device: MTLDevice) {
        self.device = device
        self.resourceManager = ResourceManager(device: device)
        
        self.testQueue = OperationQueue()
        self.testQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        self.testQueue.qualityOfService = .userInitiated
    }
    
    func scheduleTest(
        _ test: XCTestCase,
        priority: ScheduledTest.Priority = .normal,
        requirements: ResourceRequirements,
        dependencies: Set<UUID> = [],
        timeout: TimeInterval = 300
    ) -> UUID {
        let scheduledTest = ScheduledTest(
            id: UUID(),
            test: test,
            priority: priority,
            resourceRequirements: requirements,
            dependencies: dependencies,
            timeout: timeout
        )
        
        scheduledTests.append(scheduledTest)
        return scheduledTest.id
    }
    
    func executeScheduledTests() async throws {
        // Sort tests by priority and dependencies
        let sortedTests = sortTestsByPriorityAndDependencies()
        
        // Create execution groups based on available resources
        let executionGroups = createExecutionGroups(for: sortedTests)
        
        for group in executionGroups {
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                for test in group {
                    taskGroup.addTask {
                        try await self.executeTest(test)
                    }
                }
                
                try await taskGroup.waitForAll()
            }
            
            // Release resources after group completion
            resourceManager.releaseAllResources()
        }
    }
    
    private func executeTest(_ test: ScheduledTest) async throws {
        // Request resources
        guard let resources = try await resourceManager.requestResources(
            test.resourceRequirements
        ) else {
            throw SchedulerError.resourceAllocationFailed
        }
        
        // Record execution start
        let execution = TestExecution(
            test: test,
            startTime: Date(),
            assignedResources: resources,
            status: .running
        )
        runningTests[test.id] = execution
        
        // Set up timeout handler
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(test.timeout * 1_000_000_000))
            if runningTests[test.id]?.status == .running {
                runningTests[test.id]?.status = .timeout
                throw SchedulerError.testTimeout
            }
        }
        
        do {
            // Execute test
            try await test.test.executeTest()
            
            // Update status
            runningTests[test.id]?.status = .completed(.success(()))
        } catch {
            runningTests[test.id]?.status = .completed(.failure(error))
            throw error
        } finally {
            // Clean up
            timeoutTask.cancel()
            resourceManager.releaseResources(resources)
            runningTests[test.id] = nil
        }
    }
    
    private func sortTestsByPriorityAndDependencies() -> [ScheduledTest] {
        return scheduledTests.sorted { test1, test2 in
            // First sort by priority
            if test1.priority != test2.priority {
                return test1.priority.rawValue > test2.priority.rawValue
            }
            
            // Then consider dependencies
            if test2.dependencies.contains(test1.id) {
                return true
            }
            if test1.dependencies.contains(test2.id) {
                return false
            }
            
            // Finally sort by expected duration (shortest first)
            return test1.resourceRequirements.expectedDuration < 
                   test2.resourceRequirements.expectedDuration
        }
    }
    
    private func createExecutionGroups(
        for tests: [ScheduledTest]
    ) -> [[ScheduledTest]] {
        var groups: [[ScheduledTest]] = []
        var currentGroup: [ScheduledTest] = []
        var currentResources = ResourceRequirements(
            cpuCores: 0,
            memoryMB: 0,
            gpuMemoryMB: 0,
            expectedDuration: 0
        )
        
        for test in tests {
            let requirements = test.resourceRequirements
            
            // Check if adding this test would exceed available resources
            if canAddToGroup(requirements, currentResources: currentResources) {
                currentGroup.append(test)
                currentResources = ResourceRequirements(
                    cpuCores: currentResources.cpuCores + requirements.cpuCores,
                    memoryMB: currentResources.memoryMB + requirements.memoryMB,
                    gpuMemoryMB: currentResources.gpuMemoryMB + requirements.gpuMemoryMB,
                    expectedDuration: max(currentResources.expectedDuration,
                                       requirements.expectedDuration)
                )
            } else {
                // Start new group
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [test]
                currentResources = requirements
            }
        }
        
        // Add last group
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    private func canAddToGroup(
        _ requirements: ResourceRequirements,
        currentResources: ResourceRequirements
    ) -> Bool {
        let totalCPU = currentResources.cpuCores + requirements.cpuCores
        let totalMemory = currentResources.memoryMB + requirements.memoryMB
        let totalGPUMemory = currentResources.gpuMemoryMB + requirements.gpuMemoryMB
        
        return totalCPU <= ProcessInfo.processInfo.activeProcessorCount &&
               totalMemory <= resourceManager.availableMemoryMB &&
               totalGPUMemory <= resourceManager.availableGPUMemoryMB
    }
}

final class ResourceManager {
    private let device: MTLDevice
    private var allocatedCPUCores: Set<Int> = []
    private var allocatedMemoryRanges: [(start: UInt64, end: UInt64)] = []
    private var allocatedGPUMemoryRanges: [(start: UInt64, end: UInt64)] = []
    private let queue = DispatchQueue(label: "com.xcalp.resourcemanager")
    
    var availableMemoryMB: UInt64 {
        return ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
    }
    
    var availableGPUMemoryMB: UInt64 {
        return device.recommendedMaxWorkingSetSize / (1024 * 1024)
    }
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func requestResources(
        _ requirements: ResourceRequirements
    ) async throws -> AssignedResources? {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if let resources = try self.allocateResources(requirements) {
                        continuation.resume(returning: resources)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func releaseResources(_ resources: AssignedResources) {
        queue.async {
            // Release CPU cores
            self.allocatedCPUCores.subtract(resources.cpuCores)
            
            // Release memory ranges
            self.allocatedMemoryRanges.removeAll { range in
                range.start == resources.memoryRange.lowerBound &&
                range.end == resources.memoryRange.upperBound
            }
            
            // Release GPU memory ranges
            self.allocatedGPUMemoryRanges.removeAll { range in
                range.start == resources.gpuMemoryRange.lowerBound &&
                range.end == resources.gpuMemoryRange.upperBound
            }
        }
    }
    
    func releaseAllResources() {
        queue.async {
            self.allocatedCPUCores.removeAll()
            self.allocatedMemoryRanges.removeAll()
            self.allocatedGPUMemoryRanges.removeAll()
        }
    }
    
    private func allocateResources(
        _ requirements: ResourceRequirements
    ) throws -> AssignedResources? {
        // Allocate CPU cores
        let cores = try allocateCPUCores(count: requirements.cpuCores)
        guard !cores.isEmpty else { return nil }
        
        // Allocate memory
        guard let memoryRange = allocateMemory(sizeMB: requirements.memoryMB) else {
            deallocateCPUCores(cores)
            return nil
        }
        
        // Allocate GPU memory
        guard let gpuMemoryRange = allocateGPUMemory(
            sizeMB: requirements.gpuMemoryMB
        ) else {
            deallocateCPUCores(cores)
            deallocateMemory(memoryRange)
            return nil
        }
        
        return AssignedResources(
            cpuCores: Array(cores),
            memoryRange: memoryRange,
            gpuMemoryRange: gpuMemoryRange
        )
    }
    
    private func allocateCPUCores(count: Int) throws -> Set<Int> {
        let availableCores = Set(0..<ProcessInfo.processInfo.activeProcessorCount)
            .subtracting(allocatedCPUCores)
        
        guard availableCores.count >= count else {
            throw SchedulerError.insufficientResources
        }
        
        let allocated = Set(availableCores.prefix(count))
        allocatedCPUCores.formUnion(allocated)
        return allocated
    }
    
    private func allocateMemory(sizeMB: UInt64) -> Range<UInt64>? {
        let size = sizeMB * 1024 * 1024 // Convert to bytes
        var start: UInt64 = 0
        
        // Find a gap in allocated ranges
        for range in allocatedMemoryRanges.sorted(by: { $0.start < $1.start }) {
            let gap = range.start - start
            if gap >= size {
                let allocated = start..<(start + size)
                allocatedMemoryRanges.append((start: allocated.lowerBound,
                                            end: allocated.upperBound))
                return allocated
            }
            start = range.end
        }
        
        // Check if we can allocate at the end
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        if totalMemory - start >= size {
            let allocated = start..<(start + size)
            allocatedMemoryRanges.append((start: allocated.lowerBound,
                                        end: allocated.upperBound))
            return allocated
        }
        
        return nil
    }
    
    private func allocateGPUMemory(sizeMB: UInt64) -> Range<UInt64>? {
        let size = sizeMB * 1024 * 1024 // Convert to bytes
        var start: UInt64 = 0
        
        // Find a gap in allocated ranges
        for range in allocatedGPUMemoryRanges.sorted(by: { $0.start < $1.start }) {
            let gap = range.start - start
            if gap >= size {
                let allocated = start..<(start + size)
                allocatedGPUMemoryRanges.append((start: allocated.lowerBound,
                                               end: allocated.upperBound))
                return allocated
            }
            start = range.end
        }
        
        // Check if we can allocate at the end
        let totalGPUMemory = device.recommendedMaxWorkingSetSize
        if totalGPUMemory - start >= size {
            let allocated = start..<(start + size)
            allocatedGPUMemoryRanges.append((start: allocated.lowerBound,
                                           end: allocated.upperBound))
            return allocated
        }
        
        return nil
    }
    
    private func deallocateCPUCores(_ cores: Set<Int>) {
        allocatedCPUCores.subtract(cores)
    }
    
    private func deallocateMemory(_ range: Range<UInt64>) {
        allocatedMemoryRanges.removeAll { $0.start == range.lowerBound && $0.end == range.upperBound }
    }
}

enum SchedulerError: Error {
    case resourceAllocationFailed
    case insufficientResources
    case testTimeout
    case dependencyFailed
}