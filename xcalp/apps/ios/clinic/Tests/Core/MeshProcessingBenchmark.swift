import Foundation
import Metal
import QuartzCore

final class MeshProcessingBenchmark {
    private let device: MTLDevice
    private let dataGenerator: TestDataGenerator
    private let performanceMonitor: PerformanceMonitor
    private var benchmarkResults: [String: [BenchmarkMetric]] = [:]
    
    struct BenchmarkMetric {
        let timestamp: Date
        let executionTime: CFTimeInterval
        let memoryUsage: UInt64
        let gpuTime: CFTimeInterval
        let meshComplexity: Int
        let deviceUtilization: Float
    }
    
    struct BenchmarkConfig {
        let warmupRuns: Int
        let measurementRuns: Int
        let meshSizes: [Int]
        let timeoutInterval: TimeInterval
        
        static let standard = BenchmarkConfig(
            warmupRuns: 3,
            measurementRuns: 10,
            meshSizes: [1000, 10000, 100000],
            timeoutInterval: 30
        )
    }
    
    init(device: MTLDevice) {
        self.device = device
        self.dataGenerator = TestDataGenerator()
        self.performanceMonitor = PerformanceMonitor.shared
    }
    
    func runBenchmarkSuite() async throws -> BenchmarkReport {
        var report = BenchmarkReport()
        
        // Run benchmarks for different mesh types and sizes
        for meshType in TestConfiguration.testMeshTypes {
            for resolution in TestConfiguration.testMeshResolutions {
                let metrics = try await benchmarkProcessing(
                    meshType: meshType,
                    resolution: resolution
                )
                report.addMetrics(for: "\(meshType)_\(resolution)", metrics: metrics)
            }
        }
        
        // Run specialized benchmarks
        try await benchmarkMemoryScaling(&report)
        try await benchmarkConcurrentProcessing(&report)
        try await benchmarkErrorRecovery(&report)
        
        return report
    }
    
    private func benchmarkProcessing(
        meshType: TestMeshGenerator.MeshType,
        resolution: Int
    ) async throws -> [BenchmarkMetric] {
        var metrics: [BenchmarkMetric] = []
        let config = BenchmarkConfig.standard
        
        // Warmup runs
        for _ in 0..<config.warmupRuns {
            let (testMesh, _) = dataGenerator.generateTestData(
                for: .optimal,
                meshType: meshType
            )
            _ = try await processMeshWithMetrics(testMesh)
        }
        
        // Measurement runs
        for _ in 0..<config.measurementRuns {
            let (testMesh, _) = dataGenerator.generateTestData(
                for: .optimal,
                meshType: meshType
            )
            
            let metric = try await processMeshWithMetrics(testMesh)
            metrics.append(metric)
        }
        
        return metrics
    }
    
    private func processMeshWithMetrics(_ mesh: MeshData) async throws -> BenchmarkMetric {
        let commandQueue = device.makeCommandQueue()
        let startTime = CACurrentMediaTime()
        
        // Create counter set for GPU metrics
        let counterSet = MTLCounterSet.common
        let counterSampleBuffer = try device.makeCounterSampleBuffer(
            descriptor: MTLCounterSampleBufferDescriptor()
        )
        
        // Start GPU counter sampling
        commandQueue?.sampleTimestamps(
            &counterSampleBuffer.gpuStartTime,
            &counterSampleBuffer.gpuEndTime
        )
        
        // Process mesh
        let processedMesh = try await processMeshWithFullPipeline(mesh)
        
        // End GPU counter sampling
        commandQueue?.sampleTimestamps(
            &counterSampleBuffer.gpuStartTime,
            &counterSampleBuffer.gpuEndTime
        )
        
        // Calculate metrics
        let endTime = CACurrentMediaTime()
        let executionTime = endTime - startTime
        let gpuTime = counterSampleBuffer.gpuEndTime - counterSampleBuffer.gpuStartTime
        
        return BenchmarkMetric(
            timestamp: Date(),
            executionTime: executionTime,
            memoryUsage: performanceMonitor.currentMemoryUsage(),
            gpuTime: gpuTime,
            meshComplexity: mesh.vertices.count,
            deviceUtilization: Float(gpuTime / executionTime)
        )
    }
    
    private func benchmarkMemoryScaling(_ report: inout BenchmarkReport) async throws {
        let sizes = [1000, 10000, 100000, 1000000]
        
        for size in sizes {
            let testMesh = TestMeshGenerator.generateTestMesh(
                .sphere,
                resolution: Int(sqrt(Float(size)))
            )
            
            let metric = try await processMeshWithMetrics(testMesh)
            report.addMetrics(for: "memory_scaling_\(size)", metrics: [metric])
        }
    }
    
    private func benchmarkConcurrentProcessing(_ report: inout BenchmarkReport) async throws {
        let concurrencyLevels = [1, 2, 4, 8]
        
        for level in concurrencyLevels {
            var metrics: [BenchmarkMetric] = []
            
            try await withThrowingTaskGroup(of: BenchmarkMetric.self) { group in
                for _ in 0..<level {
                    group.addTask {
                        let testMesh = TestMeshGenerator.generateTestMesh(.cube)
                        return try await self.processMeshWithMetrics(testMesh)
                    }
                }
                
                for try await metric in group {
                    metrics.append(metric)
                }
            }
            
            report.addMetrics(for: "concurrent_\(level)", metrics: metrics)
        }
    }
    
    private func benchmarkErrorRecovery(_ report: inout BenchmarkReport) async throws {
        var metrics: [BenchmarkMetric] = []
        
        // Test recovery from various error conditions
        for _ in 0..<5 {
            let corruptedMesh = TestMeshGenerator.generateTestMesh(.corrupted)
            
            do {
                let metric = try await processMeshWithMetrics(corruptedMesh)
                metrics.append(metric)
            } catch {
                // Record failed attempt metrics
                let metric = BenchmarkMetric(
                    timestamp: Date(),
                    executionTime: -1,
                    memoryUsage: performanceMonitor.currentMemoryUsage(),
                    gpuTime: -1,
                    meshComplexity: corruptedMesh.vertices.count,
                    deviceUtilization: 0
                )
                metrics.append(metric)
            }
        }
        
        report.addMetrics(for: "error_recovery", metrics: metrics)
    }
}

struct BenchmarkReport {
    private var metrics: [String: [BenchmarkMetric]] = [:]
    
    mutating func addMetrics(for identifier: String, metrics: [BenchmarkMetric]) {
        self.metrics[identifier] = metrics
    }
    
    var summary: String {
        return metrics.map { id, measurements in
            let avgTime = measurements.map { $0.executionTime }.reduce(0, +) / Double(measurements.count)
            let avgMemory = measurements.map { $0.memoryUsage }.reduce(0, +) / UInt64(measurements.count)
            let avgUtil = measurements.map { $0.deviceUtilization }.reduce(0, +) / Float(measurements.count)
            
            return """
            \(id):
                Average Time: \(String(format: "%.3f", avgTime))s
                Average Memory: \(ByteCountFormatter.string(fromByteCount: Int64(avgMemory), countStyle: .memory))
                GPU Utilization: \(String(format: "%.1f%%", avgUtil * 100))
            """
        }.joined(separator: "\n\n")
    }
    
    func getMetrics(for identifier: String) -> [BenchmarkMetric]? {
        return metrics[identifier]
    }
    
    var allMetrics: [String: [BenchmarkMetric]] {
        return metrics
    }
}