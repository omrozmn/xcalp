import Foundation
import Metal
import simd
import os.log

final class FeaturePreservationPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let featureDetectionPipeline: MTLComputePipelineState
    private let featureTrackingPipeline: MTLComputePipelineState
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "FeaturePreservation")
    
    private var detectedFeatures: [AnatomicalFeature] = []
    private var featureHistory: RingBuffer<FeatureFrame>
    private let performanceMonitor = PerformanceMonitor.shared
    
    struct AnatomicalFeature: Hashable {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let type: FeatureType
        let confidence: Float
        let uniqueID: UUID
        
        enum FeatureType: String {
            case landmark
            case contour
            case junction
            case symmetryPoint
            case anatomicalBoundary
        }
        
        static func == (lhs: AnatomicalFeature, rhs: AnatomicalFeature) -> Bool {
            lhs.uniqueID == rhs.uniqueID
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(uniqueID)
        }
    }
    
    struct FeatureFrame {
        let timestamp: Date
        let features: [AnatomicalFeature]
        let transform: simd_float4x4
    }
    
    struct PreservationConfig {
        let featureRadius: Float
        let preservationStrength: Float
        let adaptiveThreshold: Bool
        let temporalSmoothing: Bool
        
        static let `default` = PreservationConfig(
            featureRadius: 0.02,
            preservationStrength: 0.9,
            adaptiveThreshold: true,
            temporalSmoothing: true
        )
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw FeaturePreservationError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.featureHistory = RingBuffer(capacity: 30)  // 1 second at 30fps
        
        let featureDetection = try loadComputePipeline(
            "detectAnatomicalFeaturesKernel",
            library: library
        )
        let featureTracking = try loadComputePipeline(
            "trackFeaturesKernel",
            library: library
        )
        
        self.featureDetectionPipeline = featureDetection
        self.featureTrackingPipeline = featureTracking
    }
    
    func processFrame(
        _ frame: MeshFrame,
        config: PreservationConfig = .default
    ) async throws -> [AnatomicalFeature] {
        let perfID = performanceMonitor.startMeasuring("featurePreservation")
        defer { performanceMonitor.endMeasuring("featurePreservation", signpostID: perfID) }
        
        // Detect new features
        let newFeatures = try await detectFeatures(frame, config: config)
        
        // Track existing features
        let trackedFeatures = try await trackFeatures(
            newFeatures,
            frame: frame,
            config: config
        )
        
        // Update feature history
        updateFeatureHistory(
            features: trackedFeatures,
            transform: frame.transform
        )
        
        // Validate feature consistency
        try validateFeatures(trackedFeatures)
        
        return trackedFeatures
    }
    
    func preserveFeatures(
        _ mesh: MeshData,
        features: [AnatomicalFeature],
        config: PreservationConfig = .default
    ) async throws -> MeshData {
        let perfID = performanceMonitor.startMeasuring("featurePreservation")
        defer { performanceMonitor.endMeasuring("featurePreservation", signpostID: perfID) }
        
        var processedMesh = mesh
        
        // Create feature buffers
        let featureBuffer = try createFeatureBuffer(features)
        let meshBuffer = try createMeshBuffer(mesh)
        
        // Apply feature preservation
        try await preserveFeaturesGPU(
            meshBuffer: meshBuffer,
            featureBuffer: featureBuffer,
            config: config
        )
        
        // Update mesh with preserved features
        processedMesh = try updateMeshWithPreservedFeatures(
            mesh: processedMesh,
            buffer: meshBuffer
        )
        
        // Validate results
        try validatePreservation(
            original: mesh,
            processed: processedMesh,
            features: features
        )
        
        return processedMesh
    }
    
    // MARK: - Private Methods
    
    private func detectFeatures(
        _ frame: MeshFrame,
        config: PreservationConfig
    ) async throws -> [AnatomicalFeature] {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FeaturePreservationError.commandEncodingFailed
        }
        
        // Set up compute pipeline
        computeEncoder.setComputePipelineState(featureDetectionPipeline)
        
        // Create and set buffers
        let meshBuffer = try createMeshBuffer(frame.mesh)
        let featureBuffer = try createEmptyFeatureBuffer()
        
        computeEncoder.setBuffer(meshBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(featureBuffer, offset: 0, index: 1)
        
        // Set detection parameters
        var params = FeatureDetectionParams(
            radius: config.featureRadius,
            threshold: config.adaptiveThreshold ? 
                calculateAdaptiveThreshold(frame) :
                ClinicalConstants.featureDetectionThreshold
        )
        
        computeEncoder.setBytes(
            &params,
            length: MemoryLayout<FeatureDetectionParams>.stride,
            index: 2
        )
        
        // Dispatch compute command
        let gridSize = getOptimalGridSize(frame.mesh.vertexCount)
        computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: getThreadgroupSize())
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Extract detected features
        return try extractFeatures(from: featureBuffer)
    }
    
    private func trackFeatures(
        _ newFeatures: [AnatomicalFeature],
        frame: MeshFrame,
        config: PreservationConfig
    ) async throws -> [AnatomicalFeature] {
        guard let previousFrame = featureHistory.last else {
            return newFeatures
        }
        
        let matchedFeatures = try await matchFeatures(
            newFeatures,
            against: previousFrame.features,
            transform: frame.transform
        )
        
        if config.temporalSmoothing {
            return smoothFeatures(
                matchedFeatures,
                history: featureHistory.elements
            )
        }
        
        return matchedFeatures
    }
    
    private func matchFeatures(
        _ currentFeatures: [AnatomicalFeature],
        against previousFeatures: [AnatomicalFeature],
        transform: simd_float4x4
    ) async throws -> [AnatomicalFeature] {
        var matches: [AnatomicalFeature] = []
        
        // Transform previous features to current frame
        let transformedFeatures = previousFeatures.map { feature in
            transformFeature(feature, by: transform)
        }
        
        // Match features using KD-tree for efficiency
        let kdTree = KDTree(points: transformedFeatures.map { $0.position })
        
        for feature in currentFeatures {
            if let nearestIndex = kdTree.findNearest(to: feature.position) {
                let previousFeature = transformedFeatures[nearestIndex]
                
                // Check if features match based on position and normal
                if isFeatureMatch(feature, previousFeature) {
                    // Preserve feature ID for tracking
                    matches.append(AnatomicalFeature(
                        position: feature.position,
                        normal: feature.normal,
                        type: feature.type,
                        confidence: feature.confidence,
                        uniqueID: previousFeature.uniqueID
                    ))
                    continue
                }
            }
            
            // No match found, add as new feature
            matches.append(feature)
        }
        
        return matches
    }
    
    private func smoothFeatures(
        _ features: [AnatomicalFeature],
        history: [FeatureFrame]
    ) -> [AnatomicalFeature] {
        var smoothedFeatures: [AnatomicalFeature] = []
        
        for feature in features {
            // Collect historical positions of this feature
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var confidences: [Float] = []
            
            for frame in history {
                if let historicalFeature = frame.features.first(where: { $0.uniqueID == feature.uniqueID }) {
                    positions.append(historicalFeature.position)
                    normals.append(historicalFeature.normal)
                    confidences.append(historicalFeature.confidence)
                }
            }
            
            // Add current position
            positions.append(feature.position)
            normals.append(feature.normal)
            confidences.append(feature.confidence)
            
            // Apply temporal smoothing
            let smoothedPosition = smoothPositions(positions, confidences: confidences)
            let smoothedNormal = smoothNormals(normals, confidences: confidences)
            
            smoothedFeatures.append(AnatomicalFeature(
                position: smoothedPosition,
                normal: smoothedNormal,
                type: feature.type,
                confidence: feature.confidence,
                uniqueID: feature.uniqueID
            ))
        }
        
        return smoothedFeatures
    }
    
    private func validateFeatures(_ features: [AnatomicalFeature]) throws {
        // Check feature density
        let density = calculateFeatureDensity(features)
        guard density >= ClinicalConstants.minimumFeatureDensity else {
            throw FeaturePreservationError.insufficientFeatureDensity(density)
        }
        
        // Check feature distribution
        let distribution = calculateFeatureDistribution(features)
        guard distribution >= ClinicalConstants.minimumFeatureDistribution else {
            throw FeaturePreservationError.poorFeatureDistribution(distribution)
        }
        
        // Check temporal consistency
        if !featureHistory.isEmpty {
            let consistency = calculateTemporalConsistency(features)
            guard consistency >= ClinicalConstants.minimumFeatureConsistency else {
                throw FeaturePreservationError.inconsistentFeatures(consistency)
            }
        }
    }
    
    private func updateFeatureHistory(
        features: [AnatomicalFeature],
        transform: simd_float4x4
    ) {
        let frame = FeatureFrame(
            timestamp: Date(),
            features: features,
            transform: transform
        )
        featureHistory.append(frame)
    }
}

// MARK: - Supporting Types

private struct FeatureDetectionParams {
    let radius: Float
    let threshold: Float
}

enum FeaturePreservationError: Error {
    case initializationFailed
    case commandEncodingFailed
    case bufferCreationFailed
    case insufficientFeatureDensity(Float)
    case poorFeatureDistribution(Float)
    case inconsistentFeatures(Float)
    case validationFailed(String)
}