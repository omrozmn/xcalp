import Metal
import MetalKit
import simd

public struct ProcessingFeature: ReducerProtocol {
    public struct State: Equatable {
        var processingStatus: ProcessingStatus = .idle
        var meshQuality: MeshQuality = .standard
        var optimizationLevel: OptimizationLevel = .balanced
        var processingProgress: Double = 0.0
        var currentError: ProcessingError?
        var performanceMetrics: PerformanceMetrics?
        var resourceUsage: ResourceUsage = .init()
        var batchSize: Int = 1000
        var processingQueue: [MeshData] = []
    }
    
    public struct PerformanceMetrics: Equatable {
        var processingTime: TimeInterval
        var gpuUtilization: Float
        var memoryUsage: UInt64
        var frameRate: Float
    }
    
    public struct ResourceUsage: Equatable {
        var cpuUsage: Float = 0
        var gpuMemory: UInt64 = 0
        var systemMemory: UInt64 = 0
        var thermalState: ProcessorThermalState = .nominal
    }
    
    public enum ProcessorThermalState: String, Equatable {
        case nominal, fair, serious, critical
    }
    
    public enum Action: Equatable {
        case startProcessing(MeshData)
        case updateProgress(Double)
        case setQuality(MeshQuality)
        case setOptimization(OptimizationLevel)
        case processingCompleted(Result<ProcessedMesh, ProcessingError>)
        case applyTexture(TextureData)
        case textureCompleted(Result<ProcessedMesh, ProcessingError>)
        case updatePerformanceMetrics(PerformanceMetrics)
        case updateResourceUsage(ResourceUsage)
        case adjustBatchSize(Int)
        case processNextBatch
        case pauseProcessing
        case resumeProcessing
    }
    
    public enum ProcessingStatus: Equatable {
        case idle
        case processing
        case optimizing
        case texturing
        case completed
        case error(String)
        case paused
    }
    
    public enum MeshQuality: String, Equatable {
        case draft = "draft"
        case standard = "standard"
        case high = "high"
    }
    
    public enum OptimizationLevel: String, Equatable {
        case speed = "speed"
        case balanced = "balanced"
        case quality = "quality"
    }
    
    public enum ProcessingError: Error, Equatable {
        case invalidMeshData
        case optimizationFailed
        case texturingFailed
        case gpuError
        case processingFailed
    }
    
    @Dependency(\.metalDevice) var metalDevice
    @Dependency(\.meshOptimizer) var meshOptimizer
    @Dependency(\.performanceMonitor) var performanceMonitor
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .startProcessing(let meshData):
                state.processingStatus = .processing
                return processMesh(meshData, quality: state.meshQuality)
                
            case .updateProgress(let progress):
                state.processingProgress = progress
                return .none
                
            case .setQuality(let quality):
                state.meshQuality = quality
                return .none
                
            case .setOptimization(let level):
                state.optimizationLevel = level
                return .none
                
            case .processingCompleted(.success(let mesh)):
                state.processingStatus = .completed
                return optimizeMesh(mesh, level: state.optimizationLevel)
                
            case .processingCompleted(.failure(let error)):
                state.processingStatus = .error(error.localizedDescription)
                state.currentError = error
                return .none
                
            case .applyTexture(let textureData):
                state.processingStatus = .texturing
                return applyTexture(textureData)
                
            case .textureCompleted(.success(let mesh)):
                state.processingStatus = .completed
                return .none
                
            case .textureCompleted(.failure(let error)):
                state.processingStatus = .error(error.localizedDescription)
                state.currentError = error
                return .none
                
            case .updatePerformanceMetrics(let metrics):
                state.performanceMetrics = metrics
                return adjustProcessingParameters(state: &state, metrics: metrics)
                
            case .updateResourceUsage(let usage):
                state.resourceUsage = usage
                return handleResourceUsage(state: &state, usage: usage)
                
            case .adjustBatchSize(let size):
                state.batchSize = size
                return .none
                
            case .processNextBatch:
                guard !state.processingQueue.isEmpty else {
                    return .none
                }
                let batch = Array(state.processingQueue.prefix(state.batchSize))
                state.processingQueue.removeFirst(min(state.batchSize, state.processingQueue.count))
                return processBatch(batch, quality: state.meshQuality)
                
            case .pauseProcessing:
                state.processingStatus = .paused
                return .none
                
            case .resumeProcessing:
                state.processingStatus = .processing
                return .send(.processNextBatch)
            }
        }
    }
    
    private func processMesh(_ meshData: MeshData, quality: MeshQuality) -> Effect<Action, Never> {
        Effect.task {
            do {
                let processedMesh = try await meshOptimizer.process(
                    meshData,
                    quality: quality,
                    device: metalDevice
                )
                return .processingCompleted(.success(processedMesh))
            } catch {
                return .processingCompleted(.failure(.processingFailed))
            }
        }
    }
    
    private func optimizeMesh(_ mesh: ProcessedMesh, level: OptimizationLevel) -> Effect<Action, Never> {
        Effect.task {
            do {
                let optimizedMesh = try await meshOptimizer.optimize(
                    mesh,
                    level: level,
                    device: metalDevice
                )
                return .processingCompleted(.success(optimizedMesh))
            } catch {
                return .processingCompleted(.failure(.optimizationFailed))
            }
        }
    }
    
    private func applyTexture(_ textureData: TextureData) -> Effect<Action, Never> {
        Effect.task {
            do {
                let texturedMesh = try await meshOptimizer.applyTexture(
                    textureData,
                    device: metalDevice
                )
                return .textureCompleted(.success(texturedMesh))
            } catch {
                return .textureCompleted(.failure(.texturingFailed))
            }
        }
    }
    
    private func processBatch(_ meshes: [MeshData], quality: MeshQuality) -> Effect<Action, Never> {
        Effect.task {
            async let performanceMetrics = performanceMonitor.getCurrentMetrics()
            async let resourceUsage = performanceMonitor.getResourceUsage()
            
            do {
                let processedMeshes = try await withThrowingTaskGroup(of: ProcessedMesh.self) { group in
                    for mesh in meshes {
                        group.addTask {
                            try await meshOptimizer.process(
                                mesh,
                                quality: quality,
                                device: metalDevice
                            )
                        }
                    }
                    
                    var results: [ProcessedMesh] = []
                    for try await mesh in group {
                        results.append(mesh)
                    }
                    return results
                }
                
                // Update metrics and continue processing
                await updateMetrics(metrics: await performanceMetrics)
                await updateResources(usage: await resourceUsage)
                
                return .processingCompleted(.success(processedMeshes.first!))
            } catch {
                return .processingCompleted(.failure(.processingFailed))
            }
        }
    }
    
    private func adjustProcessingParameters(state: inout State, metrics: PerformanceMetrics) -> Effect<Action, Never> {
        // Adjust batch size based on performance
        let newBatchSize = calculateOptimalBatchSize(
            currentSize: state.batchSize,
            processingTime: metrics.processingTime,
            gpuUtilization: metrics.gpuUtilization,
            memoryUsage: metrics.memoryUsage
        )
        
        if newBatchSize != state.batchSize {
            return .send(.adjustBatchSize(newBatchSize))
        }
        
        return .none
    }
    
    private func handleResourceUsage(state: inout State, usage: ResourceUsage) -> Effect<Action, Never> {
        switch usage.thermalState {
        case .critical:
            return .send(.pauseProcessing)
        case .serious:
            let reducedBatchSize = max(1, state.batchSize / 2)
            return .send(.adjustBatchSize(reducedBatchSize))
        case .fair, .nominal:
            if state.processingStatus == .paused {
                return .send(.resumeProcessing)
            }
        }
        return .none
    }
    
    private func calculateOptimalBatchSize(currentSize: Int, processingTime: TimeInterval, gpuUtilization: Float, memoryUsage: UInt64) -> Int {
        let targetProcessingTime: TimeInterval = 0.033 // Target 30fps
        let targetGPUUtilization: Float = 0.8
        let maxMemoryUsage: UInt64 = 150 * 1024 * 1024 // 150MB
        
        var newSize = currentSize
        
        // Adjust based on processing time
        if processingTime > targetProcessingTime {
            newSize = max(1, Int(Double(newSize) * (targetProcessingTime / processingTime)))
        }
        
        // Adjust based on GPU utilization
        if gpuUtilization > targetGPUUtilization {
            newSize = max(1, Int(Float(newSize) * (targetGPUUtilization / gpuUtilization)))
        }
        
        // Adjust based on memory usage
        if memoryUsage > maxMemoryUsage {
            newSize = max(1, Int(Double(newSize) * (Double(maxMemoryUsage) / Double(memoryUsage))))
        }
        
        return min(max(1, newSize), 5000) // Cap between 1 and 5000
    }
}
