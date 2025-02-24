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
    }
    
    public enum Action: Equatable {
        case startProcessing(MeshData)
        case updateProgress(Double)
        case setQuality(MeshQuality)
        case setOptimization(OptimizationLevel)
        case processingCompleted(Result<ProcessedMesh, ProcessingError>)
        case applyTexture(TextureData)
        case textureCompleted(Result<ProcessedMesh, ProcessingError>)
    }
    
    public enum ProcessingStatus: Equatable {
        case idle
        case processing
        case optimizing
        case texturing
        case completed
        case error(String)
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
    }
    
    @Dependency(\.metalDevice) var metalDevice
    @Dependency(\.meshOptimizer) var meshOptimizer
    
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
}
