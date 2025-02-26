import Foundation
import Metal
import simd
import os.log

final class MeshValidationSystem {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshValidationSystem")
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    enum ValidationStage {
        case preprocessing
        case reconstruction
        case optimization
        case fusion
        case postprocessing
    }
    
    struct ValidationResult {
        let isValid: Bool
        let stage: ValidationStage
        let metrics: ValidationMetrics
        let errors: [ValidationError]
        let warnings: [ValidationWarning]
    }
    
    struct ValidationMetrics {
        let vertexCount: Int
        let faceCount: Int
        let boundingBox: BoundingBox
        let surfaceArea: Float
        let volume: Float
        let manifoldness: Float
        let watertightness: Float
    }
    
    struct ValidationError: LocalizedError {
        let stage: ValidationStage
        let code: Int
        let message: String
        var errorDescription: String? { message }
    }
    
    struct ValidationWarning {
        let stage: ValidationStage
        let code: Int
        let message: String
        let recommendation: String
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw MeshProcessingError.initializationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
    }
    
    func validateMesh(_ mesh: MeshData, at stage: ValidationStage) async throws -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Perform basic sanity checks
        try validateBasicRequirements(mesh, stage: stage, errors: &errors)
        
        // Calculate validation metrics
        let metrics = try await calculateValidationMetrics(mesh)
        
        // Perform stage-specific validation
        switch stage {
        case .preprocessing:
            try await validatePreprocessing(mesh, errors: &errors, warnings: &warnings)
        case .reconstruction:
            try await validateReconstruction(mesh, errors: &errors, warnings: &warnings)
        case .optimization:
            try await validateOptimization(mesh, errors: &errors, warnings: &warnings)
        case .fusion:
            try await validateFusion(mesh, errors: &errors, warnings: &warnings)
        case .postprocessing:
            try await validatePostprocessing(mesh, errors: &errors, warnings: &warnings)
        }
        
        // Check against quality thresholds
        try await validateQualityThresholds(mesh, metrics: metrics, warnings: &warnings)
        
        let isValid = errors.isEmpty && metrics.manifoldness > 0.95 && metrics.watertightness > 0.98
        
        return ValidationResult(
            isValid: isValid,
            stage: stage,
            metrics: metrics,
            errors: errors,
            warnings: warnings
        )
    }
    
    private func validateBasicRequirements(_ mesh: MeshData, stage: ValidationStage, errors: inout [ValidationError]) {
        // Check for empty mesh
        if mesh.vertices.isEmpty {
            errors.append(ValidationError(
                stage: stage,
                code: 1001,
                message: "Mesh contains no vertices"
            ))
        }
        
        // Check for degenerate faces
        if !mesh.indices.isEmpty && mesh.indices.count % 3 != 0 {
            errors.append(ValidationError(
                stage: stage,
                code: 1002,
                message: "Invalid face count: not a multiple of 3"
            ))
        }
        
        // Check for index bounds
        if let maxIndex = mesh.indices.max(), maxIndex >= mesh.vertices.count {
            errors.append(ValidationError(
                stage: stage,
                code: 1003,
                message: "Index out of bounds: \(maxIndex) >= \(mesh.vertices.count)"
            ))
        }
        
        // Check data consistency
        if mesh.vertices.count != mesh.normals.count {
            errors.append(ValidationError(
                stage: stage,
                code: 1004,
                message: "Mismatched vertex and normal counts"
            ))
        }
    }
    
    private func calculateValidationMetrics(_ mesh: MeshData) async throws -> ValidationMetrics {
        var boundingBox = BoundingBox()
        var surfaceArea: Float = 0
        var volume: Float = 0
        
        // Calculate bounding box and surface area
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let v1 = mesh.vertices[Int(mesh.indices[i])]
            let v2 = mesh.vertices[Int(mesh.indices[i + 1])]
            let v3 = mesh.vertices[Int(mesh.indices[i + 2])]
            
            boundingBox = boundingBox.union(with: v1)
                                   .union(with: v2)
                                   .union(with: v3)
            
            // Calculate triangle area
            let edge1 = v2 - v1
            let edge2 = v3 - v1
            surfaceArea += length(cross(edge1, edge2)) * 0.5
            
            // Contribute to volume calculation
            volume += dot(v1, cross(edge1, edge2)) / 6.0
        }
        
        // Calculate manifoldness and watertightness
        let (manifoldness, watertightness) = try await calculateMeshTopology(mesh)
        
        return ValidationMetrics(
            vertexCount: mesh.vertices.count,
            faceCount: mesh.indices.count / 3,
            boundingBox: boundingBox,
            surfaceArea: surfaceArea,
            volume: abs(volume),
            manifoldness: manifoldness,
            watertightness: watertightness
        )
    }
    
    private func calculateMeshTopology(_ mesh: MeshData) async throws -> (manifoldness: Float, watertightness: Float) {
        var edgeCounts: [Edge: Int] = [:]
        var boundaryEdges = 0
        
        // Count edge occurrences
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let i1 = Int(mesh.indices[i])
            let i2 = Int(mesh.indices[i + 1])
            let i3 = Int(mesh.indices[i + 2])
            
            let edges = [
                Edge(v1: i1, v2: i2),
                Edge(v1: i2, v2: i3),
                Edge(v1: i3, v2: i1)
            ]
            
            for edge in edges {
                edgeCounts[edge, default: 0] += 1
            }
        }
        
        // Calculate topology metrics
        let totalEdges = edgeCounts.count
        var nonManifoldEdges = 0
        
        for (_, count) in edgeCounts {
            if count == 1 {
                boundaryEdges += 1
            } else if count > 2 {
                nonManifoldEdges += 1
            }
        }
        
        let manifoldness = 1.0 - Float(nonManifoldEdges) / Float(totalEdges)
        let watertightness = 1.0 - Float(boundaryEdges) / Float(totalEdges)
        
        return (manifoldness: manifoldness, watertightness: watertightness)
    }
    
    private func validatePreprocessing(_ mesh: MeshData, errors: inout [ValidationError], warnings: inout [ValidationWarning]) async throws {
        // Check point cloud density
        let density = calculatePointDensity(mesh.vertices)
        if density < MeshQualityConfig.minimumPointDensity {
            warnings.append(ValidationWarning(
                stage: .preprocessing,
                code: 2001,
                message: "Low point density detected",
                recommendation: "Consider capturing more detail or adjusting scanning parameters"
            ))
        }
        
        // Check for noise levels
        let noiseLevel = try await calculateNoiseLevel(mesh)
        if noiseLevel > MeshQualityConfig.maximumNoiseLevel {
            warnings.append(ValidationWarning(
                stage: .preprocessing,
                code: 2002,
                message: "High noise level detected",
                recommendation: "Consider applying additional smoothing or filtering"
            ))
        }
    }
    
    private func validateReconstruction(_ mesh: MeshData, errors: inout [ValidationError], warnings: inout [ValidationWarning]) async throws {
        // Check surface continuity
        let (gaps, discontinuities) = try await findSurfaceDiscontinuities(mesh)
        
        if !gaps.isEmpty {
            warnings.append(ValidationWarning(
                stage: .reconstruction,
                code: 3001,
                message: "Surface gaps detected",
                recommendation: "Consider adjusting reconstruction parameters or capturing additional data"
            ))
        }
        
        if discontinuities > mesh.indices.count / 100 {
            errors.append(ValidationError(
                stage: .reconstruction,
                code: 3002,
                message: "Excessive surface discontinuities detected"
            ))
        }
    }
    
    private func validateOptimization(_ mesh: MeshData, errors: inout [ValidationError], warnings: inout [ValidationWarning]) async throws {
        // Check mesh quality metrics
        let quality = try await calculateMeshQuality(mesh)
        
        if quality.aspectRatio > 10.0 {
            warnings.append(ValidationWarning(
                stage: .optimization,
                code: 4001,
                message: "Poor triangle aspect ratios detected",
                recommendation: "Consider additional mesh optimization passes"
            ))
        }
        
        if quality.edgeLength < 0.0001 {
            warnings.append(ValidationWarning(
                stage: .optimization,
                code: 4002,
                message: "Very small edges detected",
                recommendation: "Consider edge collapse optimization"
            ))
        }
    }
    
    private func validateFusion(_ mesh: MeshData, errors: inout [ValidationError], warnings: inout [ValidationWarning]) async throws {
        // Check fusion consistency
        let consistency = try await calculateFusionConsistency(mesh)
        
        if consistency < 0.8 {
            warnings.append(ValidationWarning(
                stage: .fusion,
                code: 5001,
                message: "Low fusion consistency detected",
                recommendation: "Consider adjusting fusion weights or improving alignment"
            ))
        }
    }
    
    private func validatePostprocessing(_ mesh: MeshData, errors: inout [ValidationError], warnings: inout [ValidationWarning]) async throws {
        // Final quality checks
        let finalQuality = try await calculateFinalQuality(mesh)
        
        if !finalQuality.isWatertight {
            errors.append(ValidationError(
                stage: .postprocessing,
                code: 6001,
                message: "Mesh is not watertight after processing"
            ))
        }
        
        if finalQuality.selfIntersections > 0 {
            warnings.append(ValidationWarning(
                stage: .postprocessing,
                code: 6002,
                message: "Self-intersections detected",
                recommendation: "Consider additional cleanup passes"
            ))
        }
    }
    
    private func validateQualityThresholds(_ mesh: MeshData, metrics: ValidationMetrics, warnings: inout [ValidationWarning]) async throws {
        // Check against configured quality thresholds
        if metrics.surfaceArea < 0.01 {
            warnings.append(ValidationWarning(
                stage: .postprocessing,
                code: 7001,
                message: "Very small surface area",
                recommendation: "Verify scan coverage and scale"
            ))
        }
        
        if metrics.watertightness < 0.98 {
            warnings.append(ValidationWarning(
                stage: .postprocessing,
                code: 7002,
                message: "Mesh is not fully watertight",
                recommendation: "Consider hole filling or additional scanning"
            ))
        }
    }
}

// Supporting types
struct Edge: Hashable {
    let v1: Int
    let v2: Int
    
    init(v1: Int, v2: Int) {
        if v1 < v2 {
            self.v1 = v1
            self.v2 = v2
        } else {
            self.v1 = v2
            self.v2 = v1
        }
    }
}

struct BoundingBox {
    var min = SIMD3<Float>(repeating: .infinity)
    var max = SIMD3<Float>(repeating: -.infinity)
    
    mutating func union(with point: SIMD3<Float>) -> BoundingBox {
        min = simd_min(min, point)
        max = simd_max(max, point)
        return self
    }
}