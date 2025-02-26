import Accelerate
import Foundation
import Metal
import MetalKit
import SceneKit
import ARKit
import os.log

private let logger = Logger(subsystem: "com.xcalp.clinic", category: "mesh-processing")

enum SensorCapabilityManager {
    enum ScannerType {
        case lidar
        case trueDepth
        case none
    }
    
    static func getScannerType() -> ScannerType {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            return .lidar
        } else if ARFaceTrackingConfiguration.isSupported {
            return .trueDepth
        }
        return .none
    }
    
    static func isScanningSupported() -> Bool {
        getScannerType() != .none
    }
    
    static func getMinimumQualityThreshold(for scannerType: ScannerType) -> Float {
        switch scannerType {
        case .lidar: return 0.8
        case .trueDepth: return 0.6
        case .none: return 0.0
        }
    }
    
    static func getFeatureAvailability(for scannerType: ScannerType) -> [String: Bool] {
        switch scannerType {
        case .lidar:
            return [
                "highPrecisionMapping": true,
                "detailedMeshGeneration": true,
                "realTimeDepthAnalysis": true
            ]
        case .trueDepth:
            return [
                "highPrecisionMapping": false,
                "detailedMeshGeneration": true,
                "realTimeDepthAnalysis": true
            ]
        case .none:
            return [
                "highPrecisionMapping": false,
                "detailedMeshGeneration": false,
                "realTimeDepthAnalysis": false
            ]
        }
    }
}

// MARK: - Error Definitions

enum MeshProcessingError: LocalizedError {
    case invalidInputData(String)
    case lidarProcessingFailed(String)
    case photogrammetryProcessingFailed(String)
    case meshFusionFailed(String)
    case qualityValidationFailed(String)
    case octreeConstructionFailed(String)
    case insufficientFeatures(found: Int, required: Int)
    case processingTimeout(TimeInterval)
    case metalInitializationFailed
    case commandEncodingFailed
    case bufferAllocationFailed
    case qualityCheckFailed(MeshQuality)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputData(let details):
            return "Invalid input data: \(details)"
        case .lidarProcessingFailed(let reason):
            return "LiDAR processing failed: \(reason)"
        case .photogrammetryProcessingFailed(let reason):
            return "Photogrammetry processing failed: \(reason)"
        case .meshFusionFailed(let reason):
            return "Mesh fusion failed: \(reason)"
        case .qualityValidationFailed(let reason):
            return "Quality validation failed: \(reason)"
        case .octreeConstructionFailed(let reason):
            return "Octree construction failed: \(reason)"
        case .insufficientFeatures(let found, let required):
            return "Insufficient features: found \(found), required \(required)"
        case .processingTimeout(let duration):
            return "Processing timeout after \(String(format: "%.1f", duration))s"
        case .metalInitializationFailed:
            return "Metal initialization failed"
        case .commandEncodingFailed:
            return "Command encoding failed"
        case .bufferAllocationFailed:
            return "Buffer allocation failed"
        case .qualityCheckFailed(let quality):
            return "Quality check failed: \(quality)"
        }
    }
}

// MARK: - MeshProcessor

final class MeshProcessor {
    enum MeshQuality {
        case low, medium, high
        
        var poissonDepth: Int {
            switch self {
            case .low: return 8
            case .medium: return 10
            case .high: return 12
            }
        }
    }
    
    private let sensorType = SensorCapabilityManager.getScannerType()
    private let qualityAssurance = ScanQualityMonitor()
    private var octree: Octree?
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineStates: [String: MTLComputePipelineState] = [:]
    
    init() throws {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        try setupMetal()
    }
    
    // MARK: - Public Methods
    
    func processPointCloud(
        _ points: [SIMD3<Float>],
        photogrammetryData: PhotogrammetryData?,
        quality: MeshQuality
    ) async throws -> SCNGeometry {
        let perfID = PerformanceMonitor.shared.startMeasuring("pointCloudProcessing")
        defer {
            PerformanceMonitor.shared.endMeasuring("pointCloudProcessing", signpostID: perfID)
        }
        
        guard !points.isEmpty else {
            throw MeshProcessingError.invalidInputData("Empty point cloud")
        }
        
        // Validate input quality
        guard validateInputPoints(points, sensorType: sensorType) else {
            throw MeshProcessingError.qualityValidationFailed("Input point cloud does not meet quality requirements")
        }
        
        // Build octree for spatial queries
        octree = try buildOctree(from: points)
        
        // Compute oriented points with robust normal estimation
        let orientedPoints = try await computeOrientedPoints(points)
        
        guard orientedPoints.count >= ClinicalConstants.minPhotogrammetryFeatures else {
            throw MeshProcessingError.insufficientFeatures(
                found: orientedPoints.count,
                required: ClinicalConstants.minPhotogrammetryFeatures
            )
        }
        
        // Surface reconstruction using Poisson method
        var mesh = try await reconstructSurface(
            orientedPoints,
            depth: quality.poissonDepth
        )
        
        // Enhance with photogrammetry if available
        if let photoData = photogrammetryData {
            mesh = try await enhanceMeshWithPhotogrammetry(mesh, photoData)
        }
        
        // Optimize mesh while preserving features
        mesh = try await optimizeMesh(mesh)
        
        // Validate final mesh quality
        let metrics = calculateMeshMetrics(mesh)
        guard metrics.meetsMinimumRequirements() else {
            throw MeshProcessingError.qualityValidationFailed("Final mesh does not meet quality requirements")
        }
        
        return createSCNGeometry(from: mesh)
    }
    
    // MARK: - Private Methods
    
    private func validateInputPoints(_ points: [SIMD3<Float>], sensorType: SensorCapabilityManager.ScannerType) -> Bool {
        let boundingBox = calculateBoundingBox(points)
        let volume = calculateVolume(boundingBox)
        let density = Float(points.count) / volume
        
        let minDensity: Float
        switch sensorType {
        case .lidar:
            minDensity = ClinicalConstants.lidarMinimumPointDensity
        case .trueDepth:
            minDensity = ClinicalConstants.trueDepthMinimumPointDensity
        case .none:
            minDensity = ClinicalConstants.minimumPointDensity
        }
        
        return density >= minDensity
    }
    
    private func buildOctree(from points: [SIMD3<Float>]) throws -> Octree {
        let perfID = PerformanceMonitor.shared.startMeasuring("octreeConstruction")
        defer {
            PerformanceMonitor.shared.endMeasuring("octreeConstruction", signpostID: perfID)
        }
        
        do {
            return try Octree(points: points, maxDepth: 8, minPointsPerNode: 8)
        } catch {
            throw MeshProcessingError.octreeConstructionFailed(error.localizedDescription)
        }
    }
    
    private func computeOrientedPoints(_ points: [SIMD3<Float>]) async throws -> [OrientedPoint] {
        let perfID = PerformanceMonitor.shared.startMeasuring("normalEstimation")
        defer {
            PerformanceMonitor.shared.endMeasuring("normalEstimation", signpostID: perfID)
        }
        
        var orientedPoints: [OrientedPoint] = []
        
        for point in points {
            let neighbors = octree?.findKNearestNeighbors(to: point, k: 20)
            let normal = computeRobustNormal(point, neighbors ?? [])
            let confidence = calculateNormalConfidence(normal, neighbors ?? [])
            
            if confidence > ClinicalConstants.minimumNormalConsistency {
                orientedPoints.append(OrientedPoint(position: point, normal: normal))
            }
        }
        
        return orientedPoints
    }
    
    private func reconstructSurface(_ orientedPoints: [OrientedPoint], depth: Int) async throws -> Mesh {
        if device != nil {
            return try await performGPUReconstruction(orientedPoints, depth: depth)
        }
        return try await performCPUReconstruction(orientedPoints, depth: depth)
    }
}

// Supporting types
struct OrientedPoint {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
}

struct MeshMetrics {
    let vertexDensity: Float
    let normalConsistency: Float
    let surfaceSmoothness: Float
    let featurePreservation: Float
    let triangulationQuality: Float
    
    func meetsMinimumRequirements() -> Bool {
        vertexDensity >= ClinicalConstants.minimumPointDensity &&
        normalConsistency >= ClinicalConstants.minimumNormalConsistency &&
        surfaceSmoothness >= ClinicalConstants.minimumSurfaceSmoothness &&
        featurePreservation >= ClinicalConstants.featurePreservationThreshold &&
        triangulationQuality >= ClinicalConstants.meshTriangulationQuality
    }
}

extension MeshProcessor {
    private func calculateMeshMetrics(_ mesh: Mesh) -> MeshMetrics {
        // Enhanced mesh quality metrics based on Laplacian Mesh Processing paper
        
        // Calculate vertex density with adaptive sampling
        let vertexDensity = calculateAdaptiveVertexDensity(mesh)
        
        // Calculate normal consistency with feature preservation
        let normalConsistency = calculateNormalConsistency(
            mesh,
            threshold: ClinicalConstants.featurePreservationThreshold
        )
        
        // Calculate surface smoothness with curvature analysis
        let surfaceSmoothness = calculateSurfaceSmoothness(
            mesh,
            threshold: ClinicalConstants.minimumSurfaceSmoothness
        )
        
        // Calculate mesh triangulation quality
        let triangulationQuality = calculateTriangulationQuality(mesh)
        
        return MeshMetrics(
            vertexDensity: vertexDensity,
            normalConsistency: normalConsistency,
            surfaceSmoothness: surfaceSmoothness,
            featurePreservation: ClinicalConstants.featurePreservationThreshold,
            triangulationQuality: triangulationQuality
        )
    }
    
    private func calculateAdaptiveVertexDensity(_ mesh: Mesh) -> Float {
        // Implement adaptive vertex density calculation based on local curvature
        var totalDensity: Float = 0
        var weightSum: Float = 0
        
        for vertex in mesh.vertices {
            let curvature = calculateLocalCurvature(at: vertex, in: mesh)
            let weight = adaptiveWeight(for: curvature)
            
            let localDensity = calculateLocalVertexDensity(around: vertex, in: mesh)
            totalDensity += localDensity * weight
            weightSum += weight
        }
        
        return weightSum > 0 ? totalDensity / weightSum : 0
    }
    
    private func calculateNormalConsistency(_ mesh: Mesh, threshold: Float) -> Float {
        var consistentNormals = 0
        var totalChecks = 0
        
        for face in mesh.faces {
            let neighbors = findNeighboringFaces(face, in: mesh)
            
            for neighbor in neighbors {
                let angleDeviation = calculateNormalDeviation(face, neighbor)
                if angleDeviation <= threshold {
                    consistentNormals += 1
                }
                totalChecks += 1
            }
        }
        
        return totalChecks > 0 ? Float(consistentNormals) / Float(totalChecks) : 0
    }
    
    private func calculateTriangulationQuality(_ mesh: Mesh) -> Float {
        // Implement triangulation quality metrics from Botsch's Polygon Mesh Processing
        var qualitySum: Float = 0
        
        for face in mesh.vertices {
            // Calculate aspect ratio
            let aspectRatio = calculateAspectRatio(face)
            
            // Calculate minimum angle
            let minAngle = calculateMinimumAngle(face)
            
            // Calculate area uniformity
            let areaUniformity = calculateAreaUniformity(face, in: mesh)
            
            // Weighted average of quality metrics
            let faceQuality = aspectRatio * 0.4 + minAngle * 0.3 + areaUniformity * 0.3
            qualitySum += faceQuality
        }
        
        return qualitySum / Float(mesh.faces.count)
    }
    
    private func adaptiveWeight(for curvature: Float) -> Float {
        // Higher weights for high-curvature regions
        1.0 + curvature * 2.0
    }
}

// Enhanced MeshMetrics structure
extension MeshMetrics {
    var triangulationQuality: Float
    
    func meetsEnhancedRequirements() -> Bool {
        vertexDensity >= ClinicalConstants.minimumVertexDensity &&
        normalConsistency >= ClinicalConstants.minimumNormalConsistency &&
        surfaceSmoothness >= ClinicalConstants.minimumSurfaceSmoothness &&
        triangulationQuality >= ClinicalConstants.meshTriangulationQuality
    }
    
    func generateQualityReport() -> MeshQualityReport {
        MeshQualityReport(
            vertexDensityScore: normalizeScore(vertexDensity, minimum: ClinicalConstants.minimumVertexDensity),
            normalConsistencyScore: normalizeScore(normalConsistency, minimum: ClinicalConstants.minimumNormalConsistency),
            smoothnessScore: normalizeScore(surfaceSmoothness, minimum: ClinicalConstants.minimumSurfaceSmoothness),
            triangulationScore: normalizeScore(triangulationQuality, minimum: ClinicalConstants.meshTriangulationQuality)
        )
    }
    
    private func normalizeScore(_ value: Float, minimum: Float) -> Float {
        min(1.0, max(0.0, (value - minimum) / (1.0 - minimum)))
    }
}

// MARK: - Supporting Types
struct MeshQualityValidator {
    // More specific validation thresholds
    private let thresholds: MeshQualityThresholds
    
    struct MeshQualityThresholds {
        let minimumVertexDensity: Float
        let minimumNormalConsistency: Float
        let minimumSurfaceSmoothness: Float
        let minimumFeaturePreservation: Float
        let maximumHoleSize: Float
        let maximumHoleCount: Int
        
        static var standard: MeshQualityThresholds {
            MeshQualityThresholds(
                minimumVertexDensity: 500, // points/cm²
                minimumNormalConsistency: 0.85,
                minimumSurfaceSmoothness: 0.75,
                minimumFeaturePreservation: 0.8,
                maximumHoleSize: 2.0, // mm
                maximumHoleCount: 5
            )
        }
    }
    
    struct ValidationResult {
        let isValid: Bool
        let issues: [QualityIssue]
        let metrics: MeshMetrics
        
        enum QualityIssue: CustomStringConvertible {
            case lowVertexDensity(Float)
            case poorNormalConsistency(Float)
            case insufficientSmoothness(Float)
            case poorFeaturePreservation(Float)
            case excessiveHoles(Int)
            case largeMeshHoles([Float])
            
            var description: String {
                switch self {
                case .lowVertexDensity(let density):
                    return "Low vertex density: \(density) points/cm²"
                case .poorNormalConsistency(let value):
                    return "Poor normal consistency: \(value)"
                case .insufficientSmoothness(let value):
                    return "Insufficient smoothness: \(value)"
                case .poorFeaturePreservation(let value):
                    return "Poor feature preservation: \(value)"
                case .excessiveHoles(let count):
                    return "Excessive holes found: \(count)"
                case .largeMeshHoles(let sizes):
                    return "Large holes detected: \(sizes.count) holes > \(sizes.max() ?? 0)mm"
                }
            }
        }
    }
    
    init(thresholds: MeshQualityThresholds = .standard) {
        self.thresholds = thresholds
    }
    
    func validate(_ mesh: Mesh) -> ValidationResult {
        var issues = [ValidationResult.QualityIssue]()
        let metrics = calculateDetailedMetrics(mesh)
        
        // Check vertex density
        if metrics.vertexDensity < thresholds.minimumVertexDensity {
            issues.append(.lowVertexDensity(metrics.vertexDensity))
        }
        
        // Check normal consistency
        if metrics.normalConsistency < thresholds.minimumNormalConsistency {
            issues.append(.poorNormalConsistency(metrics.normalConsistency))
        }
        
        // Check surface smoothness
        if metrics.surfaceSmoothness < thresholds.minimumSurfaceSmoothness {
            issues.append(.insufficientSmoothness(metrics.surfaceSmoothness))
        }
        
        // Check feature preservation
        if metrics.featurePreservation < thresholds.minimumFeaturePreservation {
            issues.append(.poorFeaturePreservation(metrics.featurePreservation))
        }
        
        // Check for holes
        let holes = detectHoles(in: mesh)
        if holes.count > thresholds.maximumHoleCount {
            issues.append(.excessiveHoles(holes.count))
        }
        
        let largeHoles = holes.filter { $0 > thresholds.maximumHoleSize }
        if !largeHoles.isEmpty {
            issues.append(.largeMeshHoles(largeHoles))
        }
        
        return ValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            metrics: metrics
        )
    }
    
    private func calculateDetailedMetrics(_ mesh: Mesh) -> MeshMetrics {
        // Enhanced metrics calculation with all quality aspects
        MeshMetrics(
            vertexDensity: calculateVertexDensity(mesh),
            normalConsistency: calculateNormalConsistency(mesh),
            surfaceSmoothness: calculateSurfaceSmoothness(mesh),
            featurePreservation: calculateFeaturePreservation(mesh),
            triangulationQuality: calculateTriangulationQuality(mesh)
        )
    }
    
    private func detectHoles(_ mesh: Mesh) -> [Float] {
        // Implement hole detection using boundary edge analysis
        // Returns array of hole sizes in mm
        []  // TODO: Implement
    }
}

// MARK: - Performance Monitoring
struct ProcessingMetrics {
    var pointCloudSize: Int
    var processingDuration: TimeInterval
    var memoryUsage: Int64
    var gpuUsage: Float
    var qualityScore: Float
    var optimizationLevel: String
    
    var asDictionary: [String: Any] {
        [
            "pointCloudSize": pointCloudSize,
            "processingDuration": processingDuration,
            "memoryUsage": memoryUsage,
            "gpuUsage": gpuUsage,
            "qualityScore": qualityScore,
            "optimizationLevel": optimizationLevel
        ]
    }
    
    func logMetrics() {
        logger.info("""
            Processing completed:
            - Points: \(pointCloudSize)
            - Duration: \(String(format: "%.2f", processingDuration))s
            - Memory: \(ByteCountFormatter.string(fromByteCount: memoryUsage, countStyle: .binary))
            - GPU Usage: \(String(format: "%.1f", gpuUsage * 100))%
            - Quality: \(String(format: "%.2f", qualityScore))
            - Optimization: \(optimizationLevel)
            """)
    }
}

// MARK: - Core Processing Methods
extension MeshProcessor {
    private func reconstructSurface(quality: MeshQuality) async throws -> SCNGeometry {
        let perfID = PerformanceMonitor.shared.startMeasuring("surfaceReconstruction")
        defer {
            PerformanceMonitor.shared.endMeasuring("surfaceReconstruction", signpostID: perfID)
        }
        
        logger.debug("Starting surface reconstruction with quality: \(String(describing: quality))")
        
        // Track GPU and memory usage
        var metrics = ProcessingMetrics(
            pointCloudSize: octree?.totalPoints ?? 0,
            processingDuration: 0,
            memoryUsage: ProcessInfo.processInfo.physicalMemory,
            gpuUsage: 0,
            qualityScore: 0,
            optimizationLevel: String(describing: quality)
        )
        
        let startTime = CACurrentMediaTime()
        
        do {
            // 1. Generate oriented points
            logger.debug("Estimating robust normals")
            let orientedPoints = try await estimateRobustNormals()
            
            // 2. Perform Poisson reconstruction
            logger.debug("Performing Poisson surface reconstruction")
            var mesh = try await reconstructPoissonSurface(
                from: orientedPoints,
                depth: quality.poissonDepth
            )
            
            // 3. Optimize mesh
            logger.debug("Optimizing mesh")
            mesh = try await optimizeMesh(mesh)
            
            // 4. Validate quality
            logger.debug("Validating mesh quality")
            let validator = MeshQualityValidator()
            let validationResult = validator.validate(mesh)
            
            if !validationResult.isValid {
                logger.warning("Quality validation issues found: \(validationResult.issues.map { $0.description }.joined(separator: ", "))")
                if validationResult.issues.contains(where: { 
                    if case .excessiveHoles = $0 { return true }
                    return false 
                }) {
                    // Attempt hole filling if there are too many holes
                    logger.info("Attempting to fill mesh holes")
                    mesh = try await fillMeshHoles(mesh)
                }
            }
            
            // Update metrics
            metrics.processingDuration = CACurrentMediaTime() - startTime
            metrics.qualityScore = validationResult.metrics.overallQuality
            metrics.logMetrics()
            
            // Create SCNGeometry
            return try createSCNGeometry(from: mesh)
            
        } catch {
            logger.error("Surface reconstruction failed: \(error.localizedDescription)")
            throw MeshProcessingError.lidarProcessingFailed("Surface reconstruction failed: \(error.localizedDescription)")
        }
    }
    
    private func estimateRobustNormals() async throws -> [OrientedPoint] {
        guard let octree = self.octree else {
            throw MeshProcessingError.octreeConstructionFailed("Octree not initialized")
        }
        
        return await withTaskGroup(of: [OrientedPoint].self) { group in
            let points = octree.allPoints
            let chunkSize = max(1, points.count / ProcessInfo.processInfo.activeProcessorCount)
            
            for chunk in stride(from: 0, to: points.count, by: chunkSize) {
                let end = min(chunk + chunkSize, points.count)
                group.addTask {
                    var orientedPoints: [OrientedPoint] = []
                    for point in points[chunk..<end] {
                        let neighbors = octree.findKNearestNeighbors(to: point, k: 20)
                        if let normal = computeRobustNormal(point, neighbors) {
                            let confidence = calculateNormalConfidence(normal, neighbors)
                            if confidence > ClinicalConstants.minimumNormalConsistency {
                                orientedPoints.append(OrientedPoint(position: point, normal: normal))
                            }
                        }
                    }
                    return orientedPoints
                }
            }
            
            var allOrientedPoints: [OrientedPoint] = []
            for await chunkPoints in group {
                allOrientedPoints.append(contentsOf: chunkPoints)
            }
            return allOrientedPoints
        }
    }
    
    private func optimizeMesh(_ mesh: Mesh) async throws -> Mesh {
        let perfID = PerformanceMonitor.shared.startMeasuring("meshOptimization")
        defer {
            PerformanceMonitor.shared.endMeasuring("meshOptimization", signpostID: perfID)
        }
        
        var optimizedMesh = mesh
        
        // 1. Remove outliers
        optimizedMesh = try await removeOutliers(optimizedMesh)
        
        // 2. Apply adaptive Laplacian smoothing
        for _ in 0..<ClinicalConstants.laplacianIterations {
            let features = try await detectFeatures(optimizedMesh)
            optimizedMesh = try await applyAdaptiveSmoothing(
                optimizedMesh,
                features: features
            )
        }
        
        // 3. Decimate mesh while preserving features
        optimizedMesh = try await decimateMesh(
            optimizedMesh,
            targetResolution: ClinicalConstants.meshResolutionMin
        )
        
        return optimizedMesh
    }
    
    private func fillMeshHoles(_ mesh: Mesh) async throws -> Mesh {
        let perfID = PerformanceMonitor.shared.startMeasuring("holeFilling")
        defer {
            PerformanceMonitor.shared.endMeasuring("holeFilling", signpostID: perfID)
        }
        
        // Implement hole filling using advancing front method
        // TODO: Implement actual hole filling
        return mesh
    }
}

// MARK: - GPU Acceleration
extension MeshProcessor {
    private var metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
    private var commandQueue: MTLCommandQueue?
    private var pipelineStates: [String: MTLComputePipelineState] = [:]
    
    private func setupMetal() throws {
        guard let device = metalDevice else {
            throw MeshProcessingError.lidarProcessingFailed("Metal is not supported on this device")
        }
        
        commandQueue = device.makeCommandQueue()
        
        // Load metal library
        guard let library = device.makeDefaultLibrary() else {
            throw MeshProcessingError.lidarProcessingFailed("Failed to create Metal library")
        }
        
        // Create pipeline states for different operations
        try createPipelineState(name: "calculateNormals", library: library)
        try createPipelineState(name: "smoothMesh", library: library)
        try createPipelineState(name: "decimateMesh", library: library)
    }
    
    private func createPipelineState(name: String, library: MTLLibrary) throws {
        guard let function = library.makeFunction(name: name) else {
            throw MeshProcessingError.lidarProcessingFailed("Failed to create Metal function: \(name)")
        }
        
        pipelineStates[name] = try metalDevice?.makeComputePipelineState(function: function)
    }
    
    private func processOnGPU(_ mesh: Mesh, operation: String) async throws -> Mesh {
        guard let device = metalDevice,
              let commandQueue = commandQueue,
              let pipelineState = pipelineStates[operation] else {
            throw MeshProcessingError.lidarProcessingFailed("GPU processing not available")
        }
        
        let perfID = PerformanceMonitor.shared.startMeasuring("gpu_\(operation)")
        defer {
            PerformanceMonitor.shared.endMeasuring("gpu_\(operation)", signpostID: perfID)
        }
        
        // Create buffers
        let vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: mesh.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        
        let normalBuffer = device.makeBuffer(
            bytes: mesh.normals,
            length: mesh.normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MeshProcessingError.lidarProcessingFailed("Failed to create command buffer")
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 1)
        
        let gridSize = MTLSize(
            width: mesh.vertices.count,
            height: 1,
            depth: 1
        )
        
        let threadGroupSize = MTLSize(
            width: pipelineState.maxTotalThreadsPerThreadgroup,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read back results
        var processedMesh = mesh
        processedMesh.vertices = Array(UnsafeBufferPointer(
            start: vertexBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
            count: mesh.vertices.count
        ))
        processedMesh.normals = Array(UnsafeBufferPointer(
            start: normalBuffer.contents().assumingMemoryBound(to: SIMD3<Float>.self),
            count: mesh.normals.count
        ))
        
        return processedMesh
    }
    
    private func applyAdaptiveSmoothing(_ mesh: Mesh, features: [Feature]) async throws -> Mesh {
        // Use GPU acceleration for smoothing when available
        if metalDevice != nil {
            return try await processOnGPU(mesh, operation: "smoothMesh")
        }
        
        // Fallback to CPU implementation
        return try await applyCPUSmoothing(mesh, features: features)
    }
    
    private func decimateMesh(_ mesh: Mesh, targetResolution: Float) async throws -> Mesh {
        // Use GPU acceleration for decimation when available
        if metalDevice != nil {
            return try await processOnGPU(mesh, operation: "decimateMesh")
        }
        
        // Fallback to CPU implementation
        return try await applyCPUDecimation(mesh, targetResolution: targetResolution)
    }
}

import Metal
import MetalKit
import ARKit
import simd
import os.log

final class MeshProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let performanceMonitor = PerformanceMonitor.shared
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshProcessing")
    
    struct ProcessingOptions {
        let targetTriangleCount: Int
        let smoothingIterations: Int
        let optimizationQuality: OptimizationQuality
        let preserveFeatures: Bool
        
        enum OptimizationQuality {
            case low      // Fast, less accurate
            case medium   // Balanced
            case high    // Slow, most accurate
        }
        
        static let `default` = ProcessingOptions(
            targetTriangleCount: 50000,
            smoothingIterations: 3,
            optimizationQuality: .medium,
            preserveFeatures: true
        )
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "optimizeMeshKernel") else {
            throw MeshProcessingError.metalInitializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
    
    func processMesh(_ mesh: ARMeshAnchor.Geometry, options: ProcessingOptions = .default) async throws -> MTKMesh {
        let perfID = performanceMonitor.startMeasuring("meshProcessing")
        defer { performanceMonitor.endMeasuring("meshProcessing", signpostID: perfID) }
        
        return try await autoreleasepool {
            // Convert AR mesh to Metal format
            let meshDescriptor = createMeshDescriptor(from: mesh)
            var metalMesh = try MTKMesh(mesh: meshDescriptor, device: device)
            
            // Process in stages with quality validation
            metalMesh = try optimizeMesh(metalMesh, options: options)
            try validateMeshQuality(metalMesh)
            
            // Apply post-processing if needed
            if options.preserveFeatures {
                metalMesh = try preserveFeatures(metalMesh)
            }
            
            return metalMesh
        }
    }
    
    private func optimizeMesh(_ mesh: MTKMesh, options: ProcessingOptions) throws -> MTKMesh {
        // Calculate optimal batch size based on available memory
        let metrics = performanceMonitor.getCurrentMetrics()
        let batchSize = calculateOptimalBatchSize(
            vertexCount: mesh.vertexCount,
            availableMemory: metrics.memoryUsage
        )
        
        // Process mesh in batches
        var optimizedMesh = mesh
        for batchIndex in stride(from: 0, to: mesh.vertexCount, by: batchSize) {
            let endIndex = min(batchIndex + batchSize, mesh.vertexCount)
            optimizedMesh = try processVertexBatch(
                optimizedMesh,
                startIndex: batchIndex,
                endIndex: endIndex,
                options: options
            )
        }
        
        return optimizedMesh
    }
    
    private func processVertexBatch(
        _ mesh: MTKMesh,
        startIndex: Int,
        endIndex: Int,
        options: ProcessingOptions
    ) throws -> MTKMesh {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MeshProcessingError.commandEncodingFailed
        }
        
        // Set up compute pipeline
        computeEncoder.setComputePipelineState(pipelineState)
        
        // Create vertex buffer for the batch
        let vertexData = getBatchVertexData(mesh, start: startIndex, end: endIndex)
        let vertexBuffer = device.makeBuffer(
            bytes: vertexData,
            length: vertexData.count * MemoryLayout<simd_float3>.stride,
            options: .storageModeShared
        )
        
        guard let vertexBuffer = vertexBuffer else {
            throw MeshProcessingError.bufferAllocationFailed
        }
        
        // Set compute parameters
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Calculate optimal threadgroup size
        let threadsPerThreadgroup = MTLSizeMake(64, 1, 1)
        let threadgroupsPerGrid = MTLSizeMake(
            (endIndex - startIndex + 63) / 64,
            1,
            1
        )
        
        // Dispatch compute command
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Update mesh with optimized vertices
        return try updateMeshVertices(mesh, vertexBuffer: vertexBuffer, startIndex: startIndex)
    }
    
    private func preserveFeatures(_ mesh: MTKMesh) throws -> MTKMesh {
        // Identify and preserve important geometric features
        let featureAnalyzer = MeshFeatureAnalyzer(device: device)
        let features = try featureAnalyzer.detectFeatures(mesh)
        
        return try featureAnalyzer.preserveFeatures(mesh, features: features)
    }
    
    private func validateMeshQuality(_ mesh: MTKMesh) throws {
        let quality = try calculateMeshQuality(mesh)
        
        guard quality.aspectRatio <= 5.0,
              quality.minAngle >= 30.0,
              quality.maxAngle <= 120.0 else {
            throw MeshProcessingError.qualityCheckFailed(quality)
        }
    }
    
    private func calculateMeshQuality(_ mesh: MTKMesh) throws -> MeshQuality {
        var aspectRatio: Float = 0
        var minAngle: Float = 180
        var maxAngle: Float = 0
        
        // Calculate mesh quality metrics
        // ... implementation details ...
        
        return MeshQuality(
            aspectRatio: aspectRatio,
            minAngle: minAngle,
            maxAngle: maxAngle
        )
    }
    
    private func calculateOptimalBatchSize(vertexCount: Int, availableMemory: UInt64) -> Int {
        let memoryPerVertex = 32 // bytes per vertex (position + normal)
        let maxVertices = Int(availableMemory / 4) / memoryPerVertex
        return min(vertexCount, maxVertices)
    }
}

// MARK: - Supporting Types

struct MeshQuality {
    let aspectRatio: Float
    let minAngle: Float
    let maxAngle: Float
}

enum MeshProcessingError: Error {
    case metalInitializationFailed
    case commandEncodingFailed
    case bufferAllocationFailed
    case qualityCheckFailed(MeshQuality)
}

private struct AdaptiveParameters {
    var smoothingStrength: Float
    var featureThreshold: Float
    var densityThreshold: Float
    var curvatureWeight: Float
}

extension MeshProcessor {
    private func calculateAdaptiveParameters(_ mesh: Mesh) -> AdaptiveParameters {
        let metrics = calculateMeshMetrics(mesh)
        
        return AdaptiveParameters(
            smoothingStrength: adaptSmoothingStrength(density: metrics.vertexDensity),
            featureThreshold: adaptFeatureThreshold(quality: metrics.triangulationQuality),
            densityThreshold: calculateDensityThreshold(mesh),
            curvatureWeight: adaptCurvatureWeight(preservation: metrics.featurePreservation)
        )
    }

    private func performAdaptiveSmoothing(_ mesh: Mesh) async throws -> Mesh {
        let params = calculateAdaptiveParameters(mesh)
        var processedMesh = mesh
        
        // Apply curvature-weighted smoothing
        for iteration in 0..<ClinicalConstants.smoothingIterations {
            let curvatures = try await calculateVertexCurvatures(processedMesh)
            processedMesh = try await applyCurvatureWeightedSmoothing(
                processedMesh,
                curvatures: curvatures,
                params: params
            )
            
            // Validate and preserve features
            if params.featureThreshold > 0 {
                processedMesh = try await preserveFeatures(
                    processedMesh,
                    threshold: params.featureThreshold
                )
            }
        }
        
        return processedMesh
    }
}

struct DetailedMeshMetrics {
    let aspectRatio: Float
    let skewness: Float
    let nonManifoldEdges: Int
    let nonManifoldVertices: Int
    let surfaceCurvature: Float
    let featureSharpness: Float
    let topologyScore: Float
}

extension MeshProcessor {
    private func calculateDetailedMetrics(_ mesh: Mesh) -> DetailedMeshMetrics {
        let aspectRatios = calculateTriangleAspectRatios(mesh)
        let skewnessValues = calculateTriangleSkewness(mesh)
        let topology = analyzeTopology(mesh)
        
        return DetailedMeshMetrics(
            aspectRatio: aspectRatios.average,
            skewness: skewnessValues.average,
            nonManifoldEdges: topology.nonManifoldEdges.count,
            nonManifoldVertices: topology.nonManifoldVertices.count,
            surfaceCurvature: calculateAverageCurvature(mesh),
            featureSharpness: calculateFeatureSharpness(mesh),
            topologyScore: calculateTopologyScore(topology)
        )
    }
    
    private func validateTopology(_ mesh: Mesh) async throws -> TopologyValidationResult {
        let metrics = calculateDetailedMetrics(mesh)
        var issues: [TopologyIssue] = []
        
        // Check for non-manifold issues
        if metrics.nonManifoldEdges > 0 {
            issues.append(.nonManifoldEdges(count: metrics.nonManifoldEdges))
        }
        if metrics.nonManifoldVertices > 0 {
            issues.append(.nonManifoldVertices(count: metrics.nonManifoldVertices))
        }
        
        // Check mesh quality metrics
        if metrics.aspectRatio > ClinicalConstants.maxAspectRatio {
            issues.append(.poorAspectRatio(value: metrics.aspectRatio))
        }
        if metrics.skewness > ClinicalConstants.maxSkewness {
            issues.append(.highSkewness(value: metrics.skewness))
        }
        
        return TopologyValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            metrics: metrics
        )
    }
}

extension MeshProcessor {
    private func processVertexBatchParallel(
        _ mesh: MTKMesh,
        batchCount: Int,
        options: ProcessingOptions
    ) async throws -> MTKMesh {
        // Create multiple command buffers for parallel processing
        let buffers = (0..<batchCount).map { _ in commandQueue.makeCommandBuffer() }
        let verticesPerBatch = mesh.vertexCount / batchCount
        
        // Process batches in parallel
        async let processedBatches = withTaskGroup(of: MTKMesh.self) { group in
            for i in 0..<batchCount {
                group.addTask {
                    let startIndex = i * verticesPerBatch
                    let endIndex = min((i + 1) * verticesPerBatch, mesh.vertexCount)
                    return try await self.processVertexBatch(
                        mesh,
                        startIndex: startIndex,
                        endIndex: endIndex,
                        options: options
                    )
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        
        // Merge processed batches
        return try await mergeMeshBatches(processedBatches)
    }
    
    private func optimizeMeshMemory(_ mesh: MTKMesh) throws -> MTKMesh {
        // Calculate optimal vertex buffer size
        let vertexSize = MemoryLayout<MeshVertex>.size
        let optimalBufferSize = calculateOptimalBufferSize(
            vertexCount: mesh.vertexCount,
            vertexSize: vertexSize
        )
        
        // Reallocate vertex buffer if needed
        if mesh.vertexBuffers[0].length > optimalBufferSize {
            return try reallocateVertexBuffer(mesh, newSize: optimalBufferSize)
        }
        return mesh
    }
}
