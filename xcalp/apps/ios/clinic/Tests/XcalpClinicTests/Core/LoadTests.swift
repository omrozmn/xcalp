import XCTest
import Metal
@testable import xcalp

final class LoadTests: XCTestCase {
    private let device: MTLDevice
    private let loadGenerator: LoadGenerator
    private let performanceMonitor: PerformanceMonitor
    private let alertHandler: TestAlertHandler
    
    override init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestError.deviceInitializationFailed
        }
        self.device = device
        self.loadGenerator = LoadGenerator(device: device)
        self.performanceMonitor = PerformanceMonitor.shared
        self.alertHandler = TestAlertHandler.shared
        try super.init()
    }
    
    func testSustainedLoad() async throws {
        let config = LoadTestConfig(
            duration: 300, // 5 minutes
            targetThroughput: 10, // meshes per second
            maxConcurrency: 8,
            meshComplexity: .medium
        )
        
        let results = try await loadGenerator.runLoadTest(config)
        
        // Verify throughput
        XCTAssertGreaterThanOrEqual(
            results.actualThroughput,
            config.targetThroughput * 0.9,
            "Failed to maintain target throughput"
        )
        
        // Verify response times
        XCTAssertLessThanOrEqual(
            results.averageResponseTime,
            1.0, // 1 second target
            "Response time exceeded target"
        )
        
        // Verify resource usage
        XCTAssertLessThanOrEqual(
            results.peakMemoryUsage,
            UInt64(TestConfiguration.maxMemoryUsage),
            "Memory usage exceeded limit"
        )
    }
    
    func testBurstLoad() async throws {
        let burstConfig = LoadTestConfig(
            duration: 30,
            targetThroughput: 50,
            maxConcurrency: 16,
            meshComplexity: .low,
            burstFactor: 3.0
        )
        
        let results = try await loadGenerator.runBurstTest(burstConfig)
        
        // Verify burst handling
        XCTAssertGreaterThanOrEqual(
            results.peakThroughput,
            burstConfig.targetThroughput * burstConfig.burstFactor,
            "Failed to handle burst load"
        )
        
        // Verify recovery
        XCTAssertLessThanOrEqual(
            results.recoveryTime,
            5.0, // 5 seconds target
            "Slow recovery from burst"
        )
    }
    
    func testResourceExhaustion() async throws {
        let exhaustionConfig = LoadTestConfig(
            duration: 60,
            targetThroughput: 20,
            maxConcurrency: 32,
            meshComplexity: .high,
            resourceLimit: 0.9 // 90% resource utilization target
        )
        
        let results = try await loadGenerator.runResourceExhaustionTest(exhaustionConfig)
        
        // Verify graceful degradation
        XCTAssertGreaterThanOrEqual(
            results.successRate,
            0.95,
            "Too many failures under resource pressure"
        )
        
        // Verify recovery actions
        XCTAssertGreaterThan(
            results.recoveryActions.count,
            0,
            "No recovery actions taken"
        )
    }
}

// Load generation infrastructure
final class LoadGenerator {
    private let device: MTLDevice
    private let testDataGenerator: TestDataGenerator
    private let processingQueue: OperationQueue
    
    init(device: MTLDevice) {
        self.device = device
        self.testDataGenerator = TestDataGenerator()
        
        self.processingQueue = OperationQueue()
        self.processingQueue.maxConcurrentOperationCount = 8
        self.processingQueue.qualityOfService = .userInitiated
    }
    
    func runLoadTest(_ config: LoadTestConfig) async throws -> LoadTestResults {
        var results = LoadTestResults()
        let startTime = Date()
        var operations: [Task<MeshData, Error>] = []
        
        while Date().timeIntervalSince(startTime) < config.duration {
            // Generate load according to configuration
            let targetOperations = Int(Double(config.targetThroughput) * config.samplingInterval)
            
            for _ in 0..<targetOperations {
                if operations.count >= config.maxConcurrency {
                    // Wait for some operations to complete
                    try await waitForOperations(&operations)
                }
                
                // Start new operation
                let operation = Task {
                    let testMesh = generateTestMesh(complexity: config.meshComplexity)
                    let startTime = CACurrentMediaTime()
                    
                    let processedMesh = try await processMeshWithFullPipeline(testMesh)
                    
                    results.recordOperation(
                        duration: CACurrentMediaTime() - startTime,
                        timestamp: Date()
                    )
                    
                    return processedMesh
                }
                
                operations.append(operation)
            }
            
            // Wait for sampling interval
            try await Task.sleep(nanoseconds: UInt64(config.samplingInterval * 1_000_000_000))
        }
        
        // Wait for remaining operations
        try await waitForOperations(&operations)
        
        return results
    }
    
    func runBurstTest(_ config: LoadTestConfig) async throws -> LoadTestResults {
        var results = LoadTestResults()
        let burstDuration = 5.0 // 5 seconds burst
        
        // Normal load phase
        try await runLoadPhase(
            duration: config.duration / 3,
            throughput: config.targetThroughput,
            config: config,
            results: &results
        )
        
        // Burst phase
        try await runLoadPhase(
            duration: burstDuration,
            throughput: config.targetThroughput * config.burstFactor,
            config: config,
            results: &results
        )
        
        // Recovery phase
        try await runLoadPhase(
            duration: config.duration / 3,
            throughput: config.targetThroughput,
            config: config,
            results: &results
        )
        
        return results
    }
    
    private func runLoadPhase(
        duration: TimeInterval,
        throughput: Double,
        config: LoadTestConfig,
        results: inout LoadTestResults
    ) async throws {
        let phaseConfig = LoadTestConfig(
            duration: duration,
            targetThroughput: throughput,
            maxConcurrency: config.maxConcurrency,
            meshComplexity: config.meshComplexity
        )
        
        let phaseResults = try await runLoadTest(phaseConfig)
        results.merge(phaseResults)
    }
    
    private func waitForOperations(_ operations: inout [Task<MeshData, Error>]) async throws {
        // Wait for at least one operation to complete
        try await withThrowingTaskGroup(of: Void.self) { group in
            for operation in operations {
                group.addTask {
                    _ = try await operation.value
                }
            }
            
            try await group.next()
        }
        
        // Remove completed operations
        operations = operations.filter { !$0.isCancelled && !$0.isComplete }
    }
    
    private func generateTestMesh(complexity: MeshComplexity) -> MeshData {
        let resolution = complexity.resolution
        return TestMeshGenerator.generateTestMesh(.sphere, resolution: resolution)
    }
}

struct LoadTestConfig {
    let duration: TimeInterval
    let targetThroughput: Double
    let maxConcurrency: Int
    let meshComplexity: MeshComplexity
    var samplingInterval: TimeInterval = 0.1
    var burstFactor: Double = 1.0
    var resourceLimit: Double = 1.0
}

enum MeshComplexity {
    case low
    case medium
    case high
    
    var resolution: Int {
        switch self {
        case .low: return 32
        case .medium: return 64
        case .high: return 128
        }
    }
}

struct LoadTestResults {
    private var operations: [(duration: TimeInterval, timestamp: Date)] = []
    var recoveryActions: [RecoveryAction] = []
    
    var actualThroughput: Double {
        guard let first = operations.first?.timestamp,
              let last = operations.last?.timestamp else {
            return 0
        }
        let duration = last.timeIntervalSince(first)
        return Double(operations.count) / duration
    }
    
    var averageResponseTime: TimeInterval {
        guard !operations.isEmpty else { return 0 }
        return operations.map { $0.duration }.reduce(0, +) / Double(operations.count)
    }
    
    var peakThroughput: Double {
        // Calculate peak throughput in 1-second windows
        let windowSize: TimeInterval = 1.0
        guard let first = operations.first?.timestamp else { return 0 }
        
        return operations
            .group(by: { Int($0.timestamp.timeIntervalSince(first) / windowSize) })
            .map { Double($0.value.count) / windowSize }
            .max() ?? 0
    }
    
    var recoveryTime: TimeInterval {
        guard let lastRecovery = recoveryActions.last else { return 0 }
        return lastRecovery.duration
    }
    
    var successRate: Double {
        guard !operations.isEmpty else { return 0 }
        let successfulOperations = operations.filter { $0.duration < 5.0 }.count
        return Double(successfulOperations) / Double(operations.count)
    }
    
    mutating func recordOperation(duration: TimeInterval, timestamp: Date) {
        operations.append((duration, timestamp))
    }
    
    mutating func merge(_ other: LoadTestResults) {
        operations.append(contentsOf: other.operations)
        recoveryActions.append(contentsOf: other.recoveryActions)
    }
}

struct RecoveryAction {
    let timestamp: Date
    let duration: TimeInterval
    let type: RecoveryType
    
    enum RecoveryType {
        case scaleDown
        case resourceCleanup
        case loadShedding
    }
}