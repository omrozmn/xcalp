import ARKit
import Foundation
import SensorCapabilityManager

class ScanProcessor {
    private let sensorType = SensorCapabilityManager.getScannerType()
    private let qualityAssurance = QualityAssurance()
    private let photogrammetryPipeline = PhotogrammetryPipeline()
    
    func processScan(_ frame: ARFrame) throws -> ProcessedScan {
        // Validate device and lighting conditions
        try validateScanningConditions(frame)
        
        // Primary: LiDAR scanning
        let pointCloud = try processLiDARData(frame)
        var confidence = calculateLiDARConfidence(frame.sceneDepth?.depthMap)
        
        // Secondary: Photogrammetry enhancement
        if let photogrammetryData = try? extractPhotogrammetryData(frame) {
            let enhancedData = try photogrammetryPipeline.process(
                photoData: photogrammetryData,
                frameCount: 30, // Process last 30 frames for SfM
                bundleAdjustment: true
            )
            
            // Fuse data with confidence weighting
            let fusedData = try fuseData(pointCloud, enhancedData, sensorType: sensorType)
            confidence = max(confidence, calculateFusionConfidence(fusedData))
            
            return ProcessedScan(
                pointCloud: fusedData,
                confidence: confidence,
                metadata: extractMetadata(frame),
                sensorType: sensorType
            )
        }
        
        // Fallback to LiDAR-only if photogrammetry fails
        return ProcessedScan(
            pointCloud: pointCloud,
            confidence: confidence,
            metadata: extractMetadata(frame),
            sensorType: sensorType
        )
    }
    
    private func enhancePointCloud(_ cloud: PointCloud, _ camera: ARCamera, sensorType: SensorCapabilityManager.ScannerType) throws -> PointCloud {
        // Implement Springer's advanced reconstruction techniques
        let filtered = filterOutliers(cloud, threshold: calculateAdaptiveThreshold(sensorType))
        let normalized = normalizePoints(filtered)
        
        // Apply sensor-specific optimization with validation
        let optimized: PointCloud
        switch sensorType {
        case .lidar:
            optimized = optimizeHighQualityPointCloud(normalized, camera)
            guard validatePointDensity(optimized, minDensity: ClinicalConstants.lidarMinimumPointDensity) else {
                throw ScanError.insufficientPointDensity
            }
        case .trueDepth:
            optimized = optimizeStandardPointCloud(normalized, camera)
            guard validatePointDensity(optimized, minDensity: ClinicalConstants.trueDepthMinimumPointDensity) else {
                throw ScanError.insufficientPointDensity
            }
        case .none:
            throw ScanError.unsupportedDevice
        }
        
        return optimized
    }
    
    private func validateMotionTracking(_ camera: ARCamera, maxDeviation: Float) -> Bool {
        let trackingState = camera.trackingState
        switch trackingState {
        case .normal:
            return camera.trackingStateReason == .none &&
                   camera.trackingQuality >= .good
        default:
            return false
        }
    }
    
    private func calculateAdaptiveThreshold(_ sensorType: SensorCapabilityManager.ScannerType) -> Float {
        switch sensorType {
        case .lidar:
            return 0.02 // 2% outlier threshold for LiDAR
        case .trueDepth:
            return 0.05 // 5% outlier threshold for TrueDepth
        case .none:
            return 0.1  // Conservative threshold for unknown sensors
        }
    }
    
    private func validatePointDensity(_ cloud: PointCloud, minDensity: Float) -> Bool {
        let density = calculatePointDensity(cloud)
        return density >= minDensity
    }
}

// Error types
enum ScanError: Error {
    case unsupportedDevice
    case insufficientLighting
    case excessiveMotion
    case insufficientPointDensity
    case insufficientPhotogrammetryQuality
    case qualityCheckFailed
    case insufficientImageData
    case fusionQualityInsufficient
}

extension ScanProcessor {
    private func extractPhotogrammetryData(_ frame: ARFrame) throws -> PhotogrammetryData {
        // Extract image and feature data according to ScienceDirect paper
        guard let currentImage = frame.capturedImage else {
            throw ScanError.insufficientImageData
        }
        
        // Extract features using Vision framework
        let features = try extractImageFeatures(currentImage)
        
        // Calculate camera parameters from ARFrame
        let cameraParams = extractCameraParameters(frame.camera)
        
        // Extract depth data if available
        let depthData = frame.sceneDepth?.depthMap
        
        return PhotogrammetryData(
            features: features,
            cameraParameters: cameraParams,
            depthMap: depthData,
            imageBuffer: currentImage,
            timestamp: frame.timestamp
        )
    }
    
    private func extractImageFeatures(_ image: CVPixelBuffer) throws -> [ImageFeature] {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        var features: [ImageFeature] = []
        
        let featureRequest = VNDetectContourRequest()
        try requestHandler.perform([featureRequest])
        
        if let results = featureRequest.results {
            features = results.compactMap { observation in
                guard let contour = observation as? VNContouredObservation else { return nil }
                return ImageFeature(
                    position: contour.normalizedPath.boundingBox.origin,
                    confidence: Float(contour.confidence),
                    type: .contour
                )
            }
        }
        
        return features
    }
    
    private func extractCameraParameters(_ camera: ARCamera) -> CameraParameters {
        CameraParameters(
            intrinsics: camera.intrinsics,
            projectionMatrix: camera.projectionMatrix,
            transform: camera.transform,
            eulerAngles: camera.eulerAngles
        )
    }
    
    private func fuseData(_ pointCloud: PointCloud, _ photogrammetry: PhotogrammetryData, sensorType: SensorCapabilityManager.ScannerType) throws -> PointCloud {
        // Implementation based on ScienceDirect photogrammetry study
        var fusedCloud = pointCloud
        
        // 1. Align photogrammetry features with point cloud
        let alignedFeatures = alignFeatures(
            photogrammetry.features,
            withPointCloud: pointCloud,
            using: photogrammetry.cameraParameters
        )
        
        // 2. Enhance point cloud with photogrammetry data
        fusedCloud = enhanceWithPhotogrammetry(
            pointCloud: fusedCloud,
            features: alignedFeatures,
            depthMap: photogrammetry.depthMap,
            sensorType: sensorType
        )
        
        // 3. Validate fusion quality
        let fusionQuality = validateFusion(
            original: pointCloud,
            fused: fusedCloud,
            features: alignedFeatures
        )
        
        guard fusionQuality >= ClinicalConstants.minimumFusionQuality else {
            throw ScanError.fusionQualityInsufficient
        }
        
        return fusedCloud
    }
    
    private func alignFeatures(_ features: [ImageFeature], withPointCloud cloud: PointCloud, using camera: CameraParameters) -> [AlignedFeature] {
        // Implement feature alignment using camera parameters
        features.compactMap { feature in
            guard let worldPoint = projectFeatureToWorld(
                feature,
                camera: camera,
                pointCloud: cloud
            ) else { return nil }
            
            return AlignedFeature(
                imageFeature: feature,
                worldPosition: worldPoint,
                confidence: feature.confidence
            )
        }
    }
    
    private func enhanceWithPhotogrammetry(
        pointCloud: PointCloud,
        features: [AlignedFeature],
        depthMap: CVPixelBuffer?,
        sensorType: SensorCapabilityManager.ScannerType
    ) -> PointCloud {
        var enhanced = pointCloud
        
        // Apply sensor-specific enhancement factors
        let enhancementFactor: Float
        switch sensorType {
        case .lidar:
            enhancementFactor = 0.7 // LiDAR data is more reliable
        case .trueDepth:
            enhancementFactor = 0.3 // TrueDepth needs more photogrammetry support
        case .none:
            enhancementFactor = 0.5
        }
        
        // Enhance point cloud using aligned features
        enhanced = features.reduce(enhanced) { cloud, feature in
            addFeatureToCloud(
                cloud,
                feature: feature,
                weight: enhancementFactor
            )
        }
        
        // If depth map is available, use it for additional enhancement
        if let depthMap = depthMap {
            enhanced = enhanceWithDepthMap(
                enhanced,
                depthMap: depthMap,
                weight: 1.0 - enhancementFactor
            )
        }
        
        return enhanced
    }
    
    private func validateFusion(
        original: PointCloud,
        fused: PointCloud,
        features: [AlignedFeature]
    ) -> Float {
        // Calculate fusion quality metrics
        let densityScore = calculateDensityImprovement(
            original: original,
            fused: fused
        )
        
        let featureAlignmentScore = calculateFeatureAlignment(
            features: features,
            pointCloud: fused
        )
        
        let consistencyScore = calculateGeometricConsistency(fused)
        
        // Weighted average of quality metrics
        return densityScore * 0.4 +
               featureAlignmentScore * 0.3 +
               consistencyScore * 0.3
    }
}

extension ScanProcessor {
    private func validatePhotogrammetryFusion(_ fusedData: PhotogrammetryData) -> Bool {
        // Validate based on latest ScienceDirect research requirements
        
        // Check minimum feature count
        guard fusedData.features.count >= ClinicalConstants.photogrammetryMinFeatures else {
            return false
        }
        
        // Validate feature match confidence
        let featureConfidences = fusedData.features.map { $0.confidence }
        let averageConfidence = featureConfidences.reduce(0, +) / Float(featureConfidences.count)
        guard averageConfidence >= ClinicalConstants.minFeatureMatchConfidence else {
            return false
        }
        
        // Check reprojection error
        guard calculateReprojectionError(fusedData) <= ClinicalConstants.maxReprojectionError else {
            return false
        }
        
        // Validate inlier ratio for robust estimation
        guard calculateInlierRatio(fusedData) >= ClinicalConstants.minInlierRatio else {
            return false
        }
        
        return true
    }
    
    private func calculateReprojectionError(_ data: PhotogrammetryData) -> Float {
        var totalError: Float = 0
        var pointCount = 0
        
        for feature in data.features {
            if let reprojected = reprojectFeature(feature, using: data.cameraParameters) {
                let error = distance(feature.position, reprojected)
                totalError += error
                pointCount += 1
            }
        }
        
        return pointCount > 0 ? totalError / Float(pointCount) : Float.infinity
    }
    
    private func calculateInlierRatio(_ data: PhotogrammetryData) -> Float {
        let inliers = data.features.filter { feature in
            guard let reprojected = reprojectFeature(feature, using: data.cameraParameters) else {
                return false
            }
            return distance(feature.position, reprojected) <= ClinicalConstants.maxReprojectionError
        }
        
        return Float(inliers.count) / Float(data.features.count)
    }
    
    private func reprojectFeature(_ feature: ImageFeature, using camera: CameraParameters) -> CGPoint? {
        // Project 3D point to 2D using camera parameters
        guard let worldPoint = feature.worldPosition else {
            return nil
        }
        
        let projected = camera.projectionMatrix * simd_float4(worldPoint, 1)
        guard projected.w != 0 else {
            return nil
        }
        
        let normalized = simd_float2(projected.x, projected.y) / projected.w
        return CGPoint(x: CGFloat(normalized.x), y: CGFloat(normalized.y))
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Float {
        let dx = Float(p1.x - p2.x)
        let dy = Float(p1.y - p2.y)
        return sqrt(dx * dx + dy * dy)
    }
    
    private func validateConsistency(_ pointCloud: PointCloud, depthMap: CVPixelBuffer?) -> Float {
        var consistencyScore: Float = 0.0
        let points = pointCloud.points
        
        autoreleasepool {
            // Calculate local neighborhood consistency
            let octree = Octree(maxPoints: 8, maxDepth: 6)
            points.forEach { octree.insert($0) }
            
            let consistencyScores = points.map { point -> Float in
                let neighbors = octree.findNeighbors(within: 0.05, of: point) // 5cm radius
                return calculateLocalConsistency(point, neighbors, depthMap)
            }
            
            consistencyScore = consistencyScores.reduce(0, +) / Float(consistencyScores.count)
        }
        
        return consistencyScore
    }

    private func calculateLocalConsistency(_ point: SIMD3<Float>, _ neighbors: [SIMD3<Float>], _ depthMap: CVPixelBuffer?) -> Float {
        guard !neighbors.isEmpty else { return 0 }
        
        // Calculate local plane normal
        let centroid = neighbors.reduce(SIMD3<Float>.zero, +) / Float(neighbors.count)
        let covariance = calculateCovarianceMatrix(points: neighbors, centroid: centroid)
        let normal = calculatePrincipalDirection(covariance)
        
        // Check depth consistency if depth map available
        var depthConsistency: Float = 1.0
        if let depthMap = depthMap {
            depthConsistency = validateDepthConsistency(point, normal, depthMap)
        }
        
        // Calculate spatial consistency
        let spatialConsistency = neighbors.map { neighbor in
            1.0 - abs(dot(normalize(neighbor - point), normal))
        }.reduce(0, +) / Float(neighbors.count)
        
        return (spatialConsistency + depthConsistency) / 2.0
    }
}

// Supporting types
struct PhotogrammetryData {
    let features: [ImageFeature]
    let cameraParameters: CameraParameters
    let depthMap: CVPixelBuffer?
    let imageBuffer: CVPixelBuffer
    let timestamp: TimeInterval
}

struct ImageFeature {
    let position: CGPoint
    let confidence: Float
    let type: FeatureType
    
    enum FeatureType {
        case contour
        case corner
        case edge
    }
}

struct CameraParameters {
    let intrinsics: simd_float3x3
    let projectionMatrix: simd_float4x4
    let transform: simd_float4x4
    let eulerAngles: simd_float3
}

struct AlignedFeature {
    let imageFeature: ImageFeature
    let worldPosition: SIMD3<Float>
    let confidence: Float
}

// COLMAP/VisualSFM integration
class PhotogrammetryPipeline {
    private var frameBuffer: RingBuffer<ARFrame>
    private let sfmProcessor: SfMProcessor
    private let mvs: MVSProcessor
    
    init() {
        frameBuffer = RingBuffer(capacity: 30)
        sfmProcessor = SfMProcessor() // COLMAP-based implementation
        mvs = MVSProcessor() // Multi-View Stereo processor
    }
    
    func process(photoData: PhotogrammetryData, frameCount: Int, bundleAdjustment: Bool) throws -> PointCloud {
        // Extract features using COLMAP's SIFT implementation
        let features = try sfmProcessor.extractFeatures(photoData.imageBuffer)
        
        // Perform Structure from Motion
        let sparseCloud = try sfmProcessor.reconstructSparse(
            features: features,
            cameraParams: photoData.cameraParameters
        )
        
        if bundleAdjustment {
            try sfmProcessor.performBundleAdjustment(sparseCloud)
        }
        
        // Dense reconstruction using MVS
        return try mvs.reconstructDense(
            sparseCloud: sparseCloud,
            depthMap: photoData.depthMap
        )
    }
}
