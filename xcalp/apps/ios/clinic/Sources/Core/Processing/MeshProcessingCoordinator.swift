import Foundation
import Metal
import simd
import os.log

/// Coordinates all mesh processing operations and ensures proper sequence of validation, optimization and quality checks
final class MeshProcessingCoordinator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshProcessingCoordinator")
    private let qualityAnalyzer: MeshQualityAnalyzer
    private let optimizer: MeshOptimizer
    private let validator: MeshValidationSystem
    private let reconstructor: MeshReconstructor
    
    private var processingQueue = OperationQueue()
    private var activeOperations: [UUID: MeshProcessingOperation] = [:]
    
    init(device: MTLDevice) throws {
        self.qualityAnalyzer = try MeshQualityAnalyzer(device: device)
        self.optimizer = try MeshOptimizer(device: device)
        self.validator = try MeshValidationSystem()
        self.reconstructor = try MeshReconstructor(device: device)
        
        processingQueue.maxConcurrentOperationCount = 1
        processingQueue.qualityOfService = .userInitiated
    }
    
    func processMesh(_ meshData: MeshData, configuration: ProcessingConfiguration) async throws -> ProcessedMeshResult {
        let operationID = UUID()
        
        // Create and configure processing operation
        let operation = MeshProcessingOperation(
            meshData: meshData,
            configuration: configuration,
            qualityAnalyzer: qualityAnalyzer,
            optimizer: optimizer,
            validator: validator,
            reconstructor: reconstructor
        )
        
        activeOperations[operationID] = operation
        
        // Execute processing pipeline
        do {
            let result = try await operation.execute()
            activeOperations.removeValue(forKey: operationID)
            return result
        } catch {
            activeOperations.removeValue(forKey: operationID)
            throw error
        }
    }
    
    func cancelProcessing(operationID: UUID) {
        if let operation = activeOperations[operationID] {
            operation.cancel()
            activeOperations.removeValue(forKey: operationID)
        }
    }
}

// MARK: - Supporting Types

struct ProcessingConfiguration {
    let qualityPreset: MeshQualityConfig.QualityPreset
    let optimizationParameters: MeshOptimizer.OptimizationParameters
    let validationStages: Set<MeshValidationSystem.ValidationStage>
    let reconstructionOptions: MeshReconstructor.ReconstructionOptions
}

struct ProcessedMeshResult {
    let mesh: MeshData
    let qualityReport: MeshQualityAnalyzer.QualityReport
    let validationResults: [MeshValidationSystem.ValidationResult]
    let optimizationStats: MeshOptimizer.OptimizationStats
    let processingTime: TimeInterval
}

// MARK: - Processing Operation

private final class MeshProcessingOperation {
    private let meshData: MeshData
    private let configuration: ProcessingConfiguration
    private let qualityAnalyzer: MeshQualityAnalyzer
    private let optimizer: MeshOptimizer
    private let validator: MeshValidationSystem
    private let reconstructor: MeshReconstructor
    
    private var isCancelled = false
    
    init(meshData: MeshData,
         configuration: ProcessingConfiguration,
         qualityAnalyzer: MeshQualityAnalyzer,
         optimizer: MeshOptimizer,
         validator: MeshValidationSystem,
         reconstructor: MeshReconstructor) {
        self.meshData = meshData
        self.configuration = configuration
        self.qualityAnalyzer = qualityAnalyzer
        self.optimizer = optimizer
        self.validator = validator
        self.reconstructor = reconstructor
    }
    
    func execute() async throws -> ProcessedMeshResult {
        let startTime = Date()
        var currentMesh = meshData
        var validationResults: [MeshValidationSystem.ValidationResult] = []
        
        // Initial quality analysis
        let initialQuality = try await qualityAnalyzer.analyzeMesh(currentMesh)
        
        // Validate preprocessing stage
        if configuration.validationStages.contains(.preprocessing) {
            let validationResult = try await validator.validateMesh(currentMesh, at: .preprocessing)
            validationResults.append(validationResult)
            
            guard validationResult.isValid else {
                throw MeshProcessingError.validationFailed(stage: .preprocessing,
                                                         errors: validationResult.errors)
            }
        }
        
        // Reconstruct if needed
        if initialQuality.needsReconstruction {
            currentMesh = try await reconstructor.reconstructMesh(
                currentMesh,
                options: configuration.reconstructionOptions
            )
            
            // Validate reconstruction
            if configuration.validationStages.contains(.reconstruction) {
                let validationResult = try await validator.validateMesh(currentMesh, at: .reconstruction)
                validationResults.append(validationResult)
                
                guard validationResult.isValid else {
                    throw MeshProcessingError.validationFailed(stage: .reconstruction,
                                                             errors: validationResult.errors)
                }
            }
        }
        
        // Optimize mesh
        let optimizationStats = try await optimizer.optimizeMesh(
            currentMesh,
            parameters: configuration.optimizationParameters
        )
        currentMesh = optimizationStats.optimizedMesh
        
        // Validate optimization
        if configuration.validationStages.contains(.optimization) {
            let validationResult = try await validator.validateMesh(currentMesh, at: .optimization)
            validationResults.append(validationResult)
            
            guard validationResult.isValid else {
                throw MeshProcessingError.validationFailed(stage: .optimization,
                                                         errors: validationResult.errors)
            }
        }
        
        // Final quality analysis
        let finalQuality = try await qualityAnalyzer.analyzeMesh(currentMesh)
        
        // Generate result
        return ProcessedMeshResult(
            mesh: currentMesh,
            qualityReport: finalQuality,
            validationResults: validationResults,
            optimizationStats: optimizationStats,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }
    
    func cancel() {
        isCancelled = true
    }
}

// MARK: - Errors

enum MeshProcessingError: LocalizedError {
    case initializationFailed
    case validationFailed(stage: MeshValidationSystem.ValidationStage, errors: [MeshValidationSystem.ValidationError])
    case meshGenerationFailed
    case qualityCheckFailed
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize mesh processing components"
        case .validationFailed(let stage, let errors):
            return "Validation failed at \(stage) stage: \(errors.map { $0.message }.joined(separator: ", "))"
        case .meshGenerationFailed:
            return "Failed to generate mesh from input data"
        case .qualityCheckFailed:
            return "Mesh quality check failed"
        }
    }
}