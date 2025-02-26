import XCTest
import Metal
@testable import xcalp

final class NormalPerformanceBenchmarks: MeshProcessingTestFixture {
    private var normalProcessor: NormalProcessor!
    private var benchmarkResults: [BenchmarkResult] = []
    
    struct BenchmarkResult {
        let name: String
        let meshSize: Int
        let duration: TimeInterval
        let memoryUsage: UInt64
        let throughput: Double // vertices per second
        let algorithm: AlgorithmType
        
        enum AlgorithmType {
            case sequential
            case parallel
            case gpuAccelerated
        }
    }
    
    override func setUp() {
        super.setUp()
        normalProcessor = try! NormalProcessor(device: device)
    }
    
    func testDataStructurePerformance() async throws {
        let meshSizes = [1000, 10000, 100000]
        
        for size in meshSizes {
            // Test array-based adjacency
            let arrayStart = CACurrentMediaTime()
            let arrayMesh = generateTestMesh(size, dataStructure: .array)
            _ = try await normalProcessor.recomputeNormals(
                arrayMesh,
                options: .init(dataStructure: .array)
            )
            let arrayTime = CACurrentMediaTime() - arrayStart
            
            // Test hash-based adjacency
            let hashStart = CACurrentMediaTime()
            let hashMesh = generateTestMesh(size, dataStructure: .hashTable)
            _ = try await normalProcessor.recomputeNormals(
                hashMesh,
                options: .init(dataStructure: .hashTable)
            )
            let hashTime = CACurrentMediaTime() - hashStart
            
            // Test graph-based adjacency
            let graphStart = CACurrentMediaTime()
            let graphMesh = generateTestMesh(size, dataStructure: .graph)
            _ = try await normalProcessor.recomputeNormals(
                graphMesh,
                options: .init(dataStructure: .graph)
            )
            let graphTime = CACurrentMediaTime() - graphStart
            
            // Record and compare results
            benchmarkResults.append(contentsOf: [
                BenchmarkResult(
                    name: "Array-based",
                    meshSize: size,
                    duration: arrayTime,
                    memoryUsage: getMemoryUsage(),
                    throughput: Double(size) / arrayTime,
                    algorithm: .sequential
                ),
                BenchmarkResult(
                    name: "Hash-based",
                    meshSize: size,
                    duration: hashTime,
                    memoryUsage: getMemoryUsage(),
                    throughput: Double(size) / hashTime,
                    algorithm: .sequential
                ),
                BenchmarkResult(
                    name: "Graph-based",
                    meshSize: size,
                    duration: graphTime,
                    memoryUsage: getMemoryUsage(),
                    throughput: Double(size) / graphTime,
                    algorithm: .sequential
                )
            ])
        }
        
        analyzeDataStructureResults()
    }
    
    func testParallelizationStrategies() async throws {
        let meshSizes = [10000, 50000, 100000]
        let threadCounts = [2, 4, 8, 16]
        
        for size in meshSizes {
            let mesh = generateTestMesh(size, dataStructure: .array)
            
            // Test different thread counts
            for threads in threadCounts {
                let start = CACurrentMediaTime()
                _ = try await normalProcessor.recomputeNormals(
                    mesh,
                    options: .init(
                        useParallelization: true,
                        threadCount: threads
                    )
                )
                let duration = CACurrentMediaTime() - start
                
                benchmarkResults.append(BenchmarkResult(
                    name: "Threads-\(threads)",
                    meshSize: size,
                    duration: duration,
                    memoryUsage: getMemoryUsage(),
                    throughput: Double(size) / duration,
                    algorithm: .parallel
                ))
            }
            
            // Test GPU acceleration
            let gpuStart = CACurrentMediaTime()
            _ = try await normalProcessor.recomputeNormals(
                mesh,
                options: .init(useGPU: true)
            )
            let gpuDuration = CACurrentMediaTime() - gpuStart
            
            benchmarkResults.append(BenchmarkResult(
                name: "GPU-Accelerated",
                meshSize: size,
                duration: gpuDuration,
                memoryUsage: getMemoryUsage(),
                throughput: Double(size) / gpuDuration,
                algorithm: .gpuAccelerated
            ))
        }
        
        analyzeParallelizationResults()
    }
    
    func testMemoryBehavior() async throws {
        let meshSizes = stride(from: 10000, through: 1000000, by: 50000)
        var memoryProfile: [(size: Int, usage: UInt64)] = []
        
        for size in meshSizes {
            let baselineMemory = getMemoryUsage()
            let mesh = generateTestMesh(Int(size), dataStructure: .array)
            
            _ = try await normalProcessor.recomputeNormals(mesh)
            
            let peakMemory = getMemoryUsage()
            memoryProfile.append((size: Int(size), usage: peakMemory - baselineMemory))
        }
        
        analyzeMemoryProfile(memoryProfile)
    }
    
    func testCacheEfficiency() async throws {
        let mesh = generateTestMesh(100000, dataStructure: .array)
        let iterations = 100
        var cacheMisses: [Int] = []
        
        for _ in 0..<iterations {
            let start = CACurrentMediaTime()
            _ = try await normalProcessor.recomputeNormals(
                mesh,
                options: .init(enableCacheAnalysis: true)
            )
            let duration = CACurrentMediaTime() - start
            
            cacheMisses.append(normalProcessor.getCacheMissCount())
        }
        
        analyzeCachePerformance(cacheMisses)
    }
    
    // MARK: - Analysis Methods
    
    private func analyzeDataStructureResults() {
        let results = benchmarkResults.filter { $0.algorithm == .sequential }
        
        // Calculate average throughput for each data structure
        let groupedResults = Dictionary(grouping: results) { $0.name }
        for (name, group) in groupedResults {
            let avgThroughput = group.map { $0.throughput }.reduce(0, +) / Double(group.count)
            print("Average throughput for \(name): \(avgThroughput) vertices/second")
        }
        
        // Find optimal data structure for different mesh sizes
        let sizeGroups = Dictionary(grouping: results) { $0.meshSize }
        for (size, group) in sizeGroups {
            if let best = group.min(by: { $0.duration < $1.duration }) {
                print("Best data structure for size \(size): \(best.name)")
            }
        }
    }
    
    private func analyzeParallelizationResults() {
        let results = benchmarkResults.filter { $0.algorithm != .sequential }
        
        // Calculate speedup relative to sequential execution
        for size in Set(results.map { $0.meshSize }) {
            let sizeResults = results.filter { $0.meshSize == size }
            if let sequential = benchmarkResults.first(where: { 
                $0.algorithm == .sequential && $0.meshSize == size 
            }) {
                for result in sizeResults {
                    let speedup = sequential.duration / result.duration
                    print("\(result.name) speedup for size \(size): \(speedup)x")
                }
            }
        }
        
        // Analyze GPU vs CPU performance crossover point
        let gpuResults = results.filter { $0.algorithm == .gpuAccelerated }
        let cpuResults = results.filter { $0.algorithm == .parallel }
        
        for size in Set(results.map { $0.meshSize }) {
            if let gpuResult = gpuResults.first(where: { $0.meshSize == size }),
               let cpuResult = cpuResults.first(where: { $0.meshSize == size }) {
                print("Size \(size) - GPU vs CPU ratio: \(cpuResult.duration / gpuResult.duration)")
            }
        }
    }
    
    private func analyzeMemoryProfile(_ profile: [(size: Int, usage: UInt64)]) {
        // Calculate memory scaling factor
        let scaling = profile.map { Double($0.usage) / Double($0.size) }
        let avgScaling = scaling.reduce(0, +) / Double(scaling.count)
        print("Average memory usage per vertex: \(avgScaling) bytes")
        
        // Detect memory leaks
        let memoryGrowth = zip(profile, profile.dropFirst()).map { 
            Double($1.usage - $0.usage) / Double($1.size - $0.size)
        }
        let avgGrowth = memoryGrowth.reduce(0, +) / Double(memoryGrowth.count)
        print("Memory growth rate: \(avgGrowth) bytes/vertex")
        
        // Check for non-linear scaling
        let correlation = calculateCorrelation(
            profile.map { Double($0.size) },
            profile.map { Double($0.usage) }
        )
        print("Memory scaling linearity (R²): \(correlation)")
    }
    
    private func analyzeCachePerformance(_ misses: [Int]) {
        let avgMisses = Double(misses.reduce(0, +)) / Double(misses.count)
        print("Average cache misses per iteration: \(avgMisses)")
        
        let stdDev = sqrt(
            misses.map { pow(Double($0) - avgMisses, 2) }.reduce(0, +) / Double(misses.count)
        )
        print("Cache miss standard deviation: \(stdDev)")
        
        // Analyze cache miss patterns
        let pattern = detectCacheMissPattern(misses)
        print("Cache miss pattern: \(pattern)")
    }
    
    // MARK: - Helper Methods
    
    private func generateTestMesh(
        _ size: Int,
        dataStructure: DataStructure
    ) -> MeshData {
        let (vertices, indices) = generateSphereMesh(resolution: Int(sqrt(Float(size))))
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: Array(repeating: .zero, count: vertices.count),
            confidence: Array(repeating: 1.0, count: vertices.count),
            metadata: MeshMetadata(source: .test)
        )
    }
    
    private func generateSphereMesh(
        resolution: Int
    ) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        for i in 0...resolution {
            let phi = Float.pi * Float(i) / Float(resolution)
            for j in 0...resolution {
                let theta = 2 * Float.pi * Float(j) / Float(resolution)
                
                let x = sin(phi) * cos(theta)
                let y = sin(phi) * sin(theta)
                let z = cos(phi)
                
                vertices.append(SIMD3<Float>(x, y, z))
                
                if i < resolution && j < resolution {
                    let current = UInt32(i * (resolution + 1) + j)
                    let next = current + 1
                    let bottom = current + UInt32(resolution + 1)
                    let bottomNext = bottom + 1
                    
                    indices.append(contentsOf: [current, next, bottom])
                    indices.append(contentsOf: [next, bottomNext, bottom])
                }
            }
        }
        
        return (vertices, indices)
    }
    
    private func calculateCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)
        
        let numerator = zip(x, y).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let denominatorX = x.map { pow($0 - meanX, 2) }.reduce(0, +)
        let denominatorY = y.map { pow($0 - meanY, 2) }.reduce(0, +)
        
        return pow(numerator, 2) / (denominatorX * denominatorY)
    }
    
    private func detectCacheMissPattern(_ misses: [Int]) -> String {
        let differences = zip(misses, misses.dropFirst()).map { $1 - $0 }
        let avgDiff = differences.reduce(0, +) / differences.count
        
        if abs(avgDiff) < 5 {
            return "Stable"
        } else if avgDiff > 0 {
            return "Increasing"
        } else {
            return "Decreasing"
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
}

enum DataStructure {
    case array
    case hashTable
    case graph
}