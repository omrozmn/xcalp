import Foundation
import ARKit
import Combine
import os.log

final class ProgressiveQualityMonitor {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ProgressiveQualityMonitor")
    private var qualityHistory: [QualityMetrics] = []
    private var adjustmentHistory: [QualityAdjustment] = []
    private let qualityThresholds = MeshQualityConfig.self
    private var currentParameters: ScanningParameters
    
    private let qualitySubject = PassthroughSubject<QualityUpdate, Never>()
    var qualityUpdates: AnyPublisher<QualityUpdate, Never> {
        qualitySubject.eraseToAnyPublisher()
    }
    
    struct QualityMetrics {
        let timestamp: Date
        let pointDensity: Float
        let surfaceCompleteness: Float
        let noiseLevel: Float
        let featurePreservation: Float
        let stability: Float
    }
    
    struct QualityUpdate {
        let metrics: QualityMetrics
        let adjustment: QualityAdjustment?
        let recommendation: String?
    }
    
    struct QualityAdjustment {
        let parameter: AdjustmentParameter
        let oldValue: Float
        let newValue: Float
        let reason: String
    }
    
    enum AdjustmentParameter {
        case searchRadius
        case spatialSigma
        case confidenceThreshold
        case featureWeight
        case smoothingFactor
    }
    
    init() {
        self.currentParameters = ScanningParameters(
            searchRadius: 0.01,
            spatialSigma: 0.005,
            confidenceThreshold: 0.7,
            featureWeight: 0.8,
            smoothingFactor: 0.2
        )
    }
    
    func processFrame(_ frame: ARFrame) async {
        let metrics = try? await calculateQualityMetrics(frame)
        guard let metrics = metrics else { return }
        
        updateQualityHistory(metrics)
        
        if let adjustment = determineQualityAdjustment(metrics) {
            applyQualityAdjustment(adjustment)
            adjustmentHistory.append(adjustment)
            
            qualitySubject.send(QualityUpdate(
                metrics: metrics,
                adjustment: adjustment,
                recommendation: generateRecommendation(for: adjustment)
            ))
        } else {
            qualitySubject.send(QualityUpdate(
                metrics: metrics,
                adjustment: nil,
                recommendation: nil
            ))
        }
    }
    
    private func calculateQualityMetrics(_ frame: ARFrame) async throws -> QualityMetrics {
        guard let sceneDepth = frame.sceneDepth,
              let confidence = frame.sceneDepth?.confidenceMap else {
            throw ScanningError.invalidFrameData
        }
        
        let pointCloud = try extractPointCloud(from: sceneDepth.depthMap)
        let stability = calculateStability(frame)
        
        return QualityMetrics(
            timestamp: Date(),
            pointDensity: calculatePointDensity(pointCloud),
            surfaceCompleteness: calculateSurfaceCompleteness(pointCloud),
            noiseLevel: calculateNoiseLevel(pointCloud),
            featurePreservation: calculateFeaturePreservation(pointCloud),
            stability: stability
        )
    }
    
    private func determineQualityAdjustment(_ metrics: QualityMetrics) -> QualityAdjustment? {
        // Check if quality has been consistently low
        guard qualityHistory.count >= 5 else { return nil }
        
        let recentMetrics = Array(qualityHistory.suffix(5))
        
        // Point density adjustment
        if recentMetrics.allSatisfy({ $0.pointDensity < qualityThresholds.minimumPointDensity }) {
            return QualityAdjustment(
                parameter: .searchRadius,
                oldValue: currentParameters.searchRadius,
                newValue: currentParameters.searchRadius * 0.8,
                reason: "Insufficient point density"
            )
        }
        
        // Noise reduction
        if recentMetrics.allSatisfy({ $0.noiseLevel > qualityThresholds.maximumNoiseLevel }) {
            return QualityAdjustment(
                parameter: .spatialSigma,
                oldValue: currentParameters.spatialSigma,
                newValue: currentParameters.spatialSigma * 1.2,
                reason: "Excessive noise level"
            )
        }
        
        // Feature preservation
        if recentMetrics.allSatisfy({ $0.featurePreservation < qualityThresholds.minimumFeaturePreservation }) {
            return QualityAdjustment(
                parameter: .featureWeight,
                oldValue: currentParameters.featureWeight,
                newValue: min(currentParameters.featureWeight * 1.2, 1.0),
                reason: "Poor feature preservation"
            )
        }
        
        return nil
    }
    
    private func applyQualityAdjustment(_ adjustment: QualityAdjustment) {
        switch adjustment.parameter {
        case .searchRadius:
            currentParameters.searchRadius = adjustment.newValue
        case .spatialSigma:
            currentParameters.spatialSigma = adjustment.newValue
        case .confidenceThreshold:
            currentParameters.confidenceThreshold = adjustment.newValue
        case .featureWeight:
            currentParameters.featureWeight = adjustment.newValue
        case .smoothingFactor:
            currentParameters.smoothingFactor = adjustment.newValue
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("ScanningParametersUpdated"),
            object: nil,
            userInfo: ["parameters": currentParameters]
        )
    }
    
    private func generateRecommendation(for adjustment: QualityAdjustment) -> String {
        switch adjustment.parameter {
        case .searchRadius:
            return "Move the device closer to capture more detail"
        case .spatialSigma:
            return "Hold the device more steady to reduce noise"
        case .confidenceThreshold:
            return "Ensure proper lighting conditions"
        case .featureWeight:
            return "Scan important features more carefully"
        case .smoothingFactor:
            return "Maintain consistent scanning speed"
        }
    }
    
    private func updateQualityHistory(_ metrics: QualityMetrics) {
        qualityHistory.append(metrics)
        if qualityHistory.count > 30 {
            qualityHistory.removeFirst()
        }
    }
    
    private func extractPointCloud(from depthMap: CVPixelBuffer) throws -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            throw ScanningError.invalidFrameData
        }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        for y in 0..<height {
            for x in 0..<width {
                let depth = baseAddress.advanced(by: y * bytesPerRow + x * 4)
                    .assumingMemoryBound(to: Float.self)
                    .pointee
                
                if depth > 0 {
                    points.append(SIMD3<Float>(
                        Float(x) / Float(width),
                        Float(y) / Float(height),
                        depth
                    ))
                }
            }
        }
        
        return points
    }
    
    private func calculatePointDensity(_ points: [SIMD3<Float>]) -> Float {
        let boundingBox = points.reduce(into: (min: SIMD3<Float>(repeating: .infinity),
                                             max: SIMD3<Float>(repeating: -.infinity))) { result, point in
            result.min = min(result.min, point)
            result.max = max(result.max, point)
        }
        
        let volume = length(boundingBox.max - boundingBox.min)
        return Float(points.count) / (volume * volume * volume)
    }
    
    private func calculateSurfaceCompleteness(_ points: [SIMD3<Float>]) -> Float {
        // Calculate coverage using spatial distribution
        let gridSize = 32
        var grid = Array(repeating: false, count: gridSize * gridSize * gridSize)
        
        for point in points {
            let x = Int(point.x * Float(gridSize))
            let y = Int(point.y * Float(gridSize))
            let z = Int(point.z * Float(gridSize))
            
            if x >= 0 && x < gridSize &&
               y >= 0 && y < gridSize &&
               z >= 0 && z < gridSize {
                grid[x + y * gridSize + z * gridSize * gridSize] = true
            }
        }
        
        let coveredCells = grid.filter { $0 }.count
        return Float(coveredCells) / Float(grid.count)
    }
    
    private func calculateNoiseLevel(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 1 else { return 0 }
        
        let spatialIndex = SpatialIndex(points: points)
        var totalVariation: Float = 0
        
        for point in points {
            let neighbors = spatialIndex.findNeighbors(for: point, radius: 0.01)
            if !neighbors.isEmpty {
                let centroid = neighbors.reduce(.zero, +) / Float(neighbors.count)
                let variation = length(point - centroid)
                totalVariation += variation
            }
        }
        
        return totalVariation / Float(points.count)
    }
    
    private func calculateFeaturePreservation(_ points: [SIMD3<Float>]) -> Float {
        guard points.count > 1 else { return 0 }
        
        let spatialIndex = SpatialIndex(points: points)
        var featureScore: Float = 0
        
        for point in points {
            let neighbors = spatialIndex.findNeighbors(for: point, radius: 0.01)
            if neighbors.count >= 3 {
                let localFeatureScore = calculateLocalFeatureScore(point, neighbors.map { points[$0] })
                featureScore += localFeatureScore
            }
        }
        
        return featureScore / Float(points.count)
    }
    
    private func calculateLocalFeatureScore(_ point: SIMD3<Float>, _ neighbors: [SIMD3<Float>]) -> Float {
        let centroid = neighbors.reduce(.zero, +) / Float(neighbors.count)
        let normal = normalize(point - centroid)
        
        let alignments = neighbors.map { neighbor in
            abs(dot(normalize(neighbor - centroid), normal))
        }
        
        return 1.0 - (alignments.reduce(0, +) / Float(alignments.count))
    }
    
    private func calculateStability(_ frame: ARFrame) -> Float {
        let transform = frame.camera.transform
        let rotationMatrix = simd_float3x3(
            transform.columns.0.xyz,
            transform.columns.1.xyz,
            transform.columns.2.xyz
        )
        
        let angle = acos((rotationMatrix.columns.0.x +
                         rotationMatrix.columns.1.y +
                         rotationMatrix.columns.2.z - 1) / 2)
        
        return 1.0 - min(abs(angle) / .pi, 1.0)
    }
}

struct ScanningParameters {
    var searchRadius: Float
    var spatialSigma: Float
    var confidenceThreshold: Float
    var featureWeight: Float
    var smoothingFactor: Float
}

private extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        SIMD3(x, y, z)
    }
}