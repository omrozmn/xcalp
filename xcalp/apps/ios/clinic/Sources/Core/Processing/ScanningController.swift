import Foundation
import Vision
import ARKit

class ScanningController: NSObject, ObservableObject, ARSessionDelegate {
    // Dependencies
    private let dataFusionProcessor: DataFusionProcessor
    private let qualityAssurance = QualityAssurance()
    private var currentMode: ScanningModes = .lidarOnly
    private var fallbackAttempts = 0
    private let maxFallbackAttempts = 2

    // Quality thresholds
    private let minLidarQuality: Float = 0.7
    private let minPhotoQuality: Float = 0.6
    private let fusionThreshold: Float = 0.8

    // Quality monitoring
    private var lidarQualityScore: Float = 0
    private var photogrammetryQualityScore: Float = 0

    private let stateManager = ScanningStateManager()
    private var pointCloudCache: LRUCache<UUID, PointCloud>?

    // MARK: - Initialization

    override init() {
        do {
            self.dataFusionProcessor = try DataFusionProcessor()
        } catch {
            fatalError("Failed to initialize DataFusionProcessor: \(error)")
        }
        super.init()
        setupPointCloudCache()
        setupMemoryHandling()
        setupMetricsLogging()
    }

    private func setupPointCloudCache() {
        pointCloudCache = LRUCache<UUID, PointCloud>(
            maxSize: ScanningConfiguration.PerformanceThresholds.maxMemoryUsage * 1024 * 1024,
            sizeFunction: { $0.memoryFootprint }
        )
    }

    private func setupMemoryHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryOptimization),
            name: NSNotification.Name("TriggerMemoryOptimization"),
            object: nil
        )
    }

    @objc private func handleMemoryOptimization() {
        // Clear non-essential caches
        pointCloudCache?.clear()
        
        // Downsample current point cloud if needed
        if let currentCloud = currentPointCloud,
           !currentCloud.canFitInMemory(limit: ScanningConfiguration.PerformanceThresholds.maxMemoryUsage * 1024 * 1024) {
            currentPointCloud = currentCloud.downsample(
                toFit: ScanningConfiguration.PerformanceThresholds.maxMemoryUsage * 1024 * 1024
            )
        }
        
        // Reduce batch size temporarily
        batchProcessor.adjustBatchSize(factor: 0.5)
        
        // Schedule batch size restoration
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            self?.batchProcessor.resetBatchSize()
        }
    }

    private func setupMetricsLogging() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.logPerformanceMetrics()
        }
    }

    private func logPerformanceMetrics() {
        let metrics = PerformanceMonitor.shared.getMetrics()
        let currentMemory = reportMemoryUsage()
        
        let performanceData: [String: Any] = [
            "memory_usage": currentMemory,
            "processing_times": metrics,
            "point_cloud_size": currentPointCloud?.points.count ?? 0,
            "cache_size": pointCloudCache?.currentSize ?? 0,
            "scanning_mode": currentMode.rawValue
        ]
        
        AnalyticsService.shared.logEvent(
            "scanning_performance_metrics",
            parameters: performanceData
        )
    }

    private func reportMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    func startScanning() {
        fallbackAttempts = 0
        
        // Try to restore previous mode if available
        if let lastMode = stateManager.retrieveLastMode() {
            currentMode = lastMode
        } else {
            currentMode = .lidarOnly
        }
        
        startScanningMode()
    }

    private func startScanningMode() {
        switch currentMode {
        case .lidarOnly:
            startLidarScanning()
        case .photogrammetryOnly:
            startPhotogrammetryScanning()
        case .hybridFusion:
            startHybridScanning()
        }
        
        stateManager.persistCurrentMode(currentMode)
    }

    private func startLidarScanning() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            handleFallback(trigger: FallbackTriggers.insufficientLidarPoints)
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

        monitorLidarQuality { quality in
            self.lidarQualityScore = quality
            if quality < self.minLidarQuality {
                self.handleFallback(trigger: FallbackTriggers.lowLidarConfidence)
            }
        }
    }

    private func startPhotogrammetryScanning() {
        // Configure and start photogrammetry session
        setupPhotogrammetrySession { success in
            if !success {
                self.handleFallback(trigger: .insufficientFeatures)
            }
        }

        monitorPhotogrammetryQuality { quality in
            if quality < ScanningQualityThresholds.minimumPhotogrammetryConfidence {
                self.handleFallback(trigger: .poorImageQuality)
            }
        }
    }

    private func startHybridScanning() {
        // Configure fusion settings based on current quality scores
        let fusionConfig = FusionConfiguration(
            lidarWeight: lidarQualityScore / (lidarQualityScore + photogrammetryQualityScore),
            photoWeight: photogrammetryQualityScore / (lidarQualityScore + photogrammetryQualityScore)
        )

        dataFusionProcessor.configureFusion(fusionConfig)

        // Monitor fusion quality
        monitorFusionQuality { quality in
            if quality < self.fusionThreshold {
                self.handleFallback(trigger: "FUSION_QUALITY_INSUFFICIENT")
            }
        }
    }

    private func handleFallback(trigger: String) {
        guard fallbackAttempts < ScanningConfiguration.TransitionParameters.maxFallbackAttempts else {
            notifyFailure("Maximum fallback attempts reached")
            return
        }
        
        fallbackAttempts += 1
        let oldMode = currentMode
        
        // Calculate backoff delay using exponential backoff
        let backoffDelay = min(
            ScanningConfiguration.TransitionParameters.baseBackoffDelay * pow(2.0, Double(fallbackAttempts)),
            ScanningConfiguration.TransitionParameters.maxBackoffDelay
        )
        
        switch currentMode {
        case .lidarOnly:
            currentMode = .photogrammetryOnly
        case .photogrammetryOnly:
            currentMode = .hybridFusion
        case .hybridFusion:
            currentMode = lidarQualityScore > photogrammetryQualityScore ? .lidarOnly : .photogrammetryOnly
        }
        
        // Log transition
        stateManager.logModeTransition(
            from: oldMode,
            to: currentMode,
            trigger: trigger
        )
        
        // Apply backoff delay and start new mode
        DispatchQueue.main.asyncAfter(deadline: .now() + backoffDelay) {
            self.startScanningMode()
        }
    }

    private func monitorLidarQuality(completion: @escaping (Float) -> Void) {
        var qualityMetrics = QualityMetrics()
        
        // Point cloud density check
        qualityMetrics.pointDensity = calculatePointCloudDensity()
        
        // Depth consistency check
        qualityMetrics.depthConsistency = validateDepthConsistency()
        
        // Surface normal consistency
        qualityMetrics.normalConsistency = validateSurfaceNormals()
        
        // Calculate final quality score
        let qualityScore = (
            qualityMetrics.pointDensity * 0.4 +
            qualityMetrics.depthConsistency * 0.4 +
            qualityMetrics.normalConsistency * 0.2
        )
        
        completion(qualityScore)
    }

    private func monitorPhotogrammetryQuality(completion: @escaping (Float) -> Void) {
        var qualityMetrics = QualityMetrics()
        
        // Feature matching quality
        qualityMetrics.featureMatchQuality = calculateFeatureMatchQuality()
        
        // Image quality assessment
        qualityMetrics.imageQuality = assessImageQuality()
        
        // Coverage completeness
        qualityMetrics.coverageCompleteness = assessCoverageCompleteness()
        
        // Calculate final quality score
        let qualityScore = (
            qualityMetrics.featureMatchQuality * 0.4 +
            qualityMetrics.imageQuality * 0.3 +
            qualityMetrics.coverageCompleteness * 0.3
        )
        
        completion(qualityScore)
    }

    private func monitorFusionQuality(completion: @escaping (Float) -> Void) {
        var fusionMetrics = FusionMetrics()
        
        // Calculate data overlap
        fusionMetrics.dataOverlap = calculateDataOverlap()
        
        // Geometric consistency
        fusionMetrics.geometricConsistency = validateGeometricConsistency()
        
        // Scale consistency
        fusionMetrics.scaleConsistency = validateScaleConsistency()
        
        // Calculate fusion quality score
        let fusionScore = (
            fusionMetrics.dataOverlap * 0.4 +
            fusionMetrics.geometricConsistency * 0.4 +
            fusionMetrics.scaleConsistency * 0.2
        )
        
        completion(fusionScore)
    }

    private func monitorFusionOpportunity() {
        // Continuously monitor both data sources for fusion opportunity
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let fusionPossible = self.qualityAssurance.shouldUseFusion(
                lidarConfidence: self.lidarQualityScore,
                photogrammetryConfidence: self.photogrammetryQualityScore
            )
            
            if fusionPossible && self.currentMode != .hybridFusion {
                self.currentMode = .hybridFusion
                self.startHybridScanning()
            }
        }
    }

    private func calculatePointCloudDensity() -> Float {
        guard let frame = currentFrame,
              let points = frame.rawFeaturePoints?.points,
              let boundingBox = frame.rawFeaturePoints?.boundingBox else {
            return 0.0
        }
        
        let volume = (boundingBox.max.x - boundingBox.min.x) *
                    (boundingBox.max.y - boundingBox.min.y) *
                    (boundingBox.max.z - boundingBox.min.z)
        
        let density = Float(points.count) / volume
        return min(density / ClinicalConstants.optimalPointDensity, 1.0)
    }

    private func validateDepthConsistency() -> Float {
        guard let depthMap = currentFrame?.sceneDepth?.depthMap else {
            return 0.0
        }
        
        var consistency: Float = 0.0
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var depthValues: [Float] = []
        for y in 0..<height {
            for x in 0..<width {
                let pixel = baseAddress?.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.size)
                let depth = pixel?.assumingMemoryBound(to: Float32.self).pointee ?? 0
                if depth > 0 {
                    depthValues.append(Float(depth))
                }
            }
        }
        
        if !depthValues.isEmpty {
            let mean = depthValues.reduce(0, +) / Float(depthValues.count)
            let variance = depthValues.map { pow($0 - mean, 2) }.reduce(0, +) / Float(depthValues.count)
            let standardDeviation = sqrt(variance)
            
            // Normalize consistency score (lower deviation = higher consistency)
            consistency = 1.0 - min(standardDeviation / mean, 1.0)
        }
        
        return consistency
    }

    private func validateSurfaceNormals() -> Float {
        guard let meshAnchors = currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }) else {
            return 0.0
        }
        
        var consistency: Float = 0.0
        var totalNormals = 0
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let normals = geometry.normals
            var normalClusters: [SIMD3<Float>: Int] = [:]
            
            // Cluster similar normals
            for i in 0..<normals.count {
                let normal = normals[i]
                let roundedNormal = SIMD3<Float>(
                    round(normal.x * 10) / 10,
                    round(normal.y * 10) / 10,
                    round(normal.z * 10) / 10
                )
                normalClusters[roundedNormal, default: 0] += 1
                totalNormals += 1
            }
            
            // Calculate consistency based on cluster sizes
            if totalNormals > 0 {
                let maxClusterSize = Float(normalClusters.values.max() ?? 0)
                consistency += maxClusterSize / Float(totalNormals)
            }
        }
        
        return meshAnchors.isEmpty ? 0.0 : consistency / Float(meshAnchors.count)
    }

    private func calculateFeatureMatchQuality() -> Float {
        guard let frame = currentFrame,
              let features = frame.rawFeaturePoints else {
            return 0.0
        }
        
        let confidences = features.points.map { $0.confidenceValue }
        let averageConfidence = confidences.reduce(0, +) / Float(confidences.count)
        
        // Weight by feature density
        let density = calculatePointCloudDensity()
        return averageConfidence * density
    }

    private func assessImageQuality() -> Float {
        guard let frame = currentFrame,
              let camera = frame.camera else {
            return 0.0
        }
        
        var quality: Float = 1.0
        
        // Check motion blur
        if camera.trackingState == .limited(.excessiveMotion) {
            quality *= 0.5
        }
        
        // Check lighting conditions
        if let lightEstimate = frame.lightEstimate {
            let normalizedIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
            quality *= min(max(normalizedIntensity, 0.0), 1.0)
        }
        
        // Check exposure
        if let imageBuffer = frame.capturedImage {
            let metadata = CMGetAttachment(imageBuffer, key: kCGImagePropertyExifDictionary, attachmentModeOut: nil)
            if let exposureValue = (metadata as? NSDictionary)?["ExposureTime"] as? Float {
                let normalizedExposure = 1.0 - min(abs(exposureValue - 0.008) / 0.008, 1.0)
                quality *= normalizedExposure
            }
        }
        
        return quality
    }

    private func assessCoverageCompleteness() -> Float {
        guard let meshAnchors = currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }) else {
            return 0.0
        }
        
        var totalArea: Float = 0
        var coveredArea: Float = 0
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            
            // Calculate mesh surface area
            for i in stride(from: 0, to: faces.count, by: 3) {
                let v1 = vertices[Int(faces[i])]
                let v2 = vertices[Int(faces[i + 1])]
                let v3 = vertices[Int(faces[i + 2])]
                
                let edge1 = v2 - v1
                let edge2 = v3 - v1
                let crossProduct = cross(edge1, edge2)
                let area = length(crossProduct) / 2
                
                totalArea += area
                
                // Check if face has valid texture coordinates
                if geometry.hasValidTexture(forFaceIndex: i) {
                    coveredArea += area
                }
            }
        }
        
        return totalArea > 0 ? coveredArea / totalArea : 0.0
    }

    private func calculateDataOverlap() -> Float {
        guard let frame = currentFrame,
              let depthMap = frame.sceneDepth?.depthMap,
              let meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor }) else {
            return 0.0
        }
        
        var overlap: Float = 0.0
        let projectionMatrix = frame.camera.projectionMatrix
        let viewMatrix = frame.camera.viewMatrix
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            
            var projectedPoints = 0
            var overlappingPoints = 0
            
            for vertex in vertices {
                // Project vertex to screen space
                let worldPoint = anchor.transform * simd_float4(vertex, 1)
                let clipSpacePoint = projectionMatrix * viewMatrix * worldPoint
                let ndcPoint = clipSpacePoint.xy / clipSpacePoint.w
                
                // Check if point is in frame
                if abs(ndcPoint.x) <= 1.0 && abs(ndcPoint.y) <= 1.0 {
                    projectedPoints += 1
                    
                    // Compare with depth map
                    let screenX = Int((ndcPoint.x + 1.0) * 0.5 * Float(CVPixelBufferGetWidth(depthMap)))
                    let screenY = Int((ndcPoint.y + 1.0) * 0.5 * Float(CVPixelBufferGetHeight(depthMap)))
                    
                    if let depth = getDepthValue(from: depthMap, at: (screenX, screenY)) {
                        let vertexDepth = -worldPoint.z
                        if abs(depth - vertexDepth) < 0.1 { // 10cm threshold
                            overlappingPoints += 1
                        }
                    }
                }
            }
            
            if projectedPoints > 0 {
                overlap += Float(overlappingPoints) / Float(projectedPoints)
            }
        }
        
        return meshAnchors.isEmpty ? 0.0 : overlap / Float(meshAnchors.count)
    }

    private func getDepthValue(from depthMap: CVPixelBuffer, at point: (Int, Int)) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        guard point.0 >= 0 && point.0 < width && point.1 >= 0 && point.1 < height else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pixel = baseAddress?.advanced(by: point.1 * bytesPerRow + point.0 * MemoryLayout<Float32>.size)
        
        return pixel?.assumingMemoryBound(to: Float32.self).pointee
    }

    private func validateGeometricConsistency() -> Float {
        guard let frame = currentFrame,
              let meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor }),
              let features = frame.rawFeaturePoints else {
            return 0.0
        }
        
        var consistency: Float = 0.0
        let featurePoints = features.points
        
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let normals = geometry.normals
            
            var localConsistency: Float = 0.0
            var validPoints = 0
            
            // Check each feature point against nearest mesh vertices
            for featurePoint in featurePoints {
                // Find closest vertex
                if let (closestVertex, closestNormal, distance) = findClosestVertex(
                    point: featurePoint,
                    vertices: vertices,
                    normals: normals,
                    transform: anchor.transform
                ) {
                    // Only consider points within threshold distance
                    if distance < ClinicalConstants.maximumDepthDiscontinuity {
                        // Calculate geometric consistency based on normal alignment
                        let featureNormal = normalize(featurePoint - closestVertex)
                        let alignment = abs(dot(featureNormal, closestNormal))
                        
                        localConsistency += alignment
                        validPoints += 1
                    }
                }
            }
            
            if validPoints > 0 {
                consistency += localConsistency / Float(validPoints)
            }
        }
        
        return meshAnchors.isEmpty ? 0.0 : consistency / Float(meshAnchors.count)
    }

    private func validateScaleConsistency() -> Float {
        guard let frame = currentFrame,
              let lidarMesh = getLidarMesh(from: frame),
              let photoPoints = getPhotogrammetryPoints(from: frame) else {
            return 0.0
        }
        
        // Calculate scale ratios between corresponding feature points
        var scaleRatios: [Float] = []
        let lidarPoints = extractKeyPoints(from: lidarMesh)
        
        // Find corresponding point pairs
        let correspondences = findCorrespondences(
            lidarPoints: lidarPoints,
            photoPoints: photoPoints,
            maxDistance: ClinicalConstants.maximumDepthDiscontinuity
        )
        
        // Calculate scale ratios between corresponding pairs
        for pair in correspondences {
            let lidarScale = calculateLocalScale(around: pair.lidar, points: lidarPoints)
            let photoScale = calculateLocalScale(around: pair.photo, points: photoPoints)
            
            if lidarScale > 0 && photoScale > 0 {
                scaleRatios.append(min(lidarScale / photoScale, photoScale / lidarScale))
            }
        }
        
        // Calculate consistency score from scale ratios
        if !scaleRatios.isEmpty {
            let averageRatio = scaleRatios.reduce(0, +) / Float(scaleRatios.count)
            let variance = scaleRatios.map { pow($0 - averageRatio, 2) }.reduce(0, +) / Float(scaleRatios.count)
            
            // Higher score for lower variance in scale ratios
            return 1.0 - sqrt(variance)
        }
        
        return 0.0
    }

    private func setupPhotogrammetrySession(completion: @escaping (Bool) -> Void) {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "photogrammetrySetup",
            category: "scanning"
        )
        
        // Configure camera for optimal photogrammetry
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.smoothedSceneDepth]
        configuration.environmentTexturing = .automatic
        
        // Set up feature extraction
        let featureExtractor = VNSequenceRequestHandler()
        let featureRequest = VNDetectContourRequest()
        
        // Configure feature detection parameters
        featureRequest.contrastAdjustment = 1.0
        featureRequest.detectDarkOnLight = true
        
        // Start session with quality monitoring
        session.run(configuration)
        monitorSessionQuality { quality in
            let success = quality >= ClinicalConstants.minimumPhotogrammetryConfidence
            
            PerformanceMonitor.shared.endMeasuring(
                "photogrammetrySetup",
                signpostID: perfID,
                category: "scanning"
            )
            
            completion(success)
        }
    }

    // Helper methods for geometric and scale validation
    private func findClosestVertex(
        point: SIMD3<Float>,
        vertices: ARGeometrySource,
        normals: ARGeometrySource,
        transform: simd_float4x4
    ) -> (vertex: SIMD3<Float>, normal: SIMD3<Float>, distance: Float)? {
        var closestVertex: SIMD3<Float>?
        var closestNormal: SIMD3<Float>?
        var minDistance = Float.infinity
        
        for i in 0..<vertices.count {
            let vertex = vertices[i]
            let worldVertex = transform.transformPoint(vertex)
            let distance = length(worldVertex - point)
            
            if distance < minDistance {
                minDistance = distance
                closestVertex = worldVertex
                closestNormal = transform.transformDirection(normals[i])
            }
        }
        
        if let vertex = closestVertex, let normal = closestNormal {
            return (vertex, normal, minDistance)
        }
        
        return nil
    }

    private func calculateLocalScale(around point: SIMD3<Float>, points: [SIMD3<Float>]) -> Float {
        // Find K nearest neighbors
        let k = min(10, points.count)
        let neighbors = findKNearestNeighbors(to: point, in: points, k: k)
        
        // Calculate average distance to neighbors as local scale
        let averageDistance = neighbors.map { length($0 - point) }.reduce(0, +) / Float(neighbors.count)
        return averageDistance
    }

    private func findKNearestNeighbors(
        to point: SIMD3<Float>,
        in points: [SIMD3<Float>],
        k: Int
    ) -> [SIMD3<Float>] {
        let sortedPoints = points.sorted {
            length($0 - point) < length($1 - point)
        }
        return Array(sortedPoints.prefix(k))
    }

    private func findCorrespondences(
        lidarPoints: [SIMD3<Float>],
        photoPoints: [SIMD3<Float>],
        maxDistance: Float
    ) -> [(lidar: SIMD3<Float>, photo: SIMD3<Float>)] {
        var correspondences: [(SIMD3<Float>, SIMD3<Float>)] = []
        
        for lidarPoint in lidarPoints {
            if let closestPhoto = photoPoints.min(by: {
                length($0 - lidarPoint) < length($1 - lidarPoint)
            }) {
                let distance = length(closestPhoto - lidarPoint)
                if distance < maxDistance {
                    correspondences.append((lidarPoint, closestPhoto))
                }
            }
        }
        
        return correspondences
    }

    private func getLidarMesh(from frame: ARFrame) -> ARMeshGeometry? {
        frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .first?.geometry
    }

    private func getPhotogrammetryPoints(from frame: ARFrame) -> [SIMD3<Float>]? {
        frame.rawFeaturePoints?.points
    }

    private func extractKeyPoints(from mesh: ARMeshGeometry) -> [SIMD3<Float>] {
        var keyPoints: [SIMD3<Float>] = []
        let vertices = mesh.vertices
        let normals = mesh.normals
        
        // Extract vertices with high curvature or distinctive features
        for i in 0..<vertices.count {
            let normal = normals[i]
            let vertex = vertices[i]
            
            // Simple curvature estimation using normal variation
            let neighborNormals = findNeighborNormals(for: i, in: mesh)
            let curvature = calculateCurvature(normal: normal, neighborNormals: neighborNormals)
            
            if curvature > 0.5 { // High curvature threshold
                keyPoints.append(vertex)
            }
        }
        
        return keyPoints
    }

    private func findNeighborNormals(for index: Int, in mesh: ARMeshGeometry) -> [SIMD3<Float>] {
        var neighbors: [SIMD3<Float>] = []
        let normals = mesh.normals
        let faces = mesh.faces
        
        // Find faces containing the vertex
        for i in stride(from: 0, to: faces.count, by: 3) {
            let indices = [
                Int(faces[i]),
                Int(faces[i + 1]),
                Int(faces[i + 2])
            ]
            
            if indices.contains(index) {
                // Add normals of connected vertices
                indices.forEach { neighborIndex in
                    if neighborIndex != index {
                        neighbors.append(normals[neighborIndex])
                    }
                }
            }
        }
        
        return neighbors
    }

    private func calculateCurvature(normal: SIMD3<Float>, neighborNormals: [SIMD3<Float>]) -> Float {
        guard !neighborNormals.isEmpty else { return 0.0 }
        
        // Calculate average difference between normal and neighbor normals
        let totalDifference = neighborNormals.reduce(0.0) { sum, neighborNormal in
            sum + (1.0 - abs(dot(normal, neighborNormal)))
        }
        
        return totalDifference / Float(neighborNormals.count)
    }

    private func enableDataFusion() {
        // Enable real-time fusion of LiDAR and photogrammetry data
        dataFusionProcessor.fuseData()
    }

    private func notifyFailure(_ message: String) {
        // Handle complete failure of both scanning methods
        print("Scanning failed: \(message)")
    }

    private func monitorQualityMetrics() {
        // Update quality metrics every frame
        monitorLidarQuality { lidarQuality in
            self.lidarQualityScore = lidarQuality
            self.updateQualityMetrics()
        }
        
        monitorPhotogrammetryQuality { photoQuality in
            self.photogrammetryQualityScore = photoQuality
            self.updateQualityMetrics()
        }
    }

    private func updateQualityMetrics() {
        let metrics: [String: Float] = [
            "lidar_quality": lidarQualityScore,
            "photo_quality": photogrammetryQualityScore,
            "point_density": calculatePointCloudDensity(),
            "surface_completeness": calculateSurfaceCompleteness(),
            "noise_level": calculateNoiseLevel(),
            "feature_preservation": calculateFeaturePreservation()
        ]
        
        stateManager.updateQualityMetrics(metrics)
        
        // Check against thresholds
        if metrics["lidar_quality"]! < ScanningConfiguration.QualityThresholds.minLidarQuality {
            handleFallback(trigger: "LOW_LIDAR_QUALITY")
        }
        
        if metrics["photo_quality"]! < ScanningConfiguration.QualityThresholds.minPhotoQuality {
            handleFallback(trigger: "LOW_PHOTO_QUALITY")
        }
    }

    // Performance optimized point cloud processing
    private func processPointCloud(_ points: [SIMD3<Float>], mode: ScanningModes) {
        let cloudID = UUID()
        let batchSize = 1000
        
        let processingGroup = DispatchGroup()
        let processingQueue = DispatchQueue(
            label: "com.xcalp.pointcloud.processing",
            attributes: .concurrent
        )
        
        var processedBatches: [[SIMD3<Float>]] = Array(
            repeating: [],
            count: (points.count + batchSize - 1) / batchSize
        )
        
        // Process in batches
        for (index, batch) in points.chunked(into: batchSize).enumerated() {
            processingQueue.async(group: processingGroup) {
                autoreleasepool {
                    let processed = self.processPointBatch(batch, mode: mode)
                    processedBatches[index] = processed
                }
            }
        }
        
        // Wait for all batches to complete
        processingGroup.wait()
        
        // Merge results
        let processedPoints = processedBatches.flatMap { $0 }
        
        // Cache with TTL
        pointCloudCache?.set(
            PointCloud(points: processedPoints), 
            for: cloudID, 
            ttl: .minutes(5)
        )
    }

    private func processPointBatch(_ points: [SIMD3<Float>], mode: ScanningMode) -> [SIMD3<Float>] {
        // Release memory for previous batch
        autoreleasepool {
            applyQualityFilters(to: points, mode: mode)
        }
    }
}

// Extension for handling AR session updates
extension ScanningController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process depth and point cloud data
        if let depthData = frame.sceneDepth?.depthMap {
            processDepthData(depthData)
        }
    }
    
    private func processDepthData(_ depthMap: CVPixelBuffer) {
        let perfID = PerformanceMonitor.shared.startMeasuring(
            "depthProcessing",
            category: "scanning"
        )
        
        // Update quality metrics
        monitorLidarQuality { quality in
            self.lidarQualityScore = quality
            
            // Log performance metrics
            AnalyticsService.shared.logScanQuality(
                quality: quality >= 0.8 ? .good : .poor,
                meshDensity: self.calculatePointCloudDensity(),
                duration: ProcessInfo.processInfo.systemUptime
            )
        }
        
        PerformanceMonitor.shared.endMeasuring(
            "depthProcessing",
            signpostID: perfID,
            category: "scanning"
        )
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle session failures
        handleSessionError(error)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Handle interruptions (e.g. phone call)
        pauseScanning()
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Resume scanning with appropriate mode
        resumeScanning()
    }
    
    private func handleSessionError(_ error: Error) {
        logger.error("AR session failed: \(error.localizedDescription)")
        
        if let arError = error as? ARError {
            switch arError.code {
            case .sensorUnavailable, .sensorFailed:
                fallback(to: .photogrammetryOnly)
            case .worldTrackingFailed:
                resetTracking()
            default:
                notifyFailure(error.localizedDescription)
            }
        }
    }
    
    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func pauseScanning() {
        session.pause()
        // Store current state for resumption
        previousMode = currentMode
    }
    
    private func resumeScanning() {
        // Restore previous scanning mode if possible
        if let mode = previousMode {
            currentMode = mode
            startScanning()
        } else {
            // Default to LiDAR if no previous mode
            currentMode = .lidarOnly
            startLidarScanning()
        }
    }
    
    private func fallback(to mode: ScanningModes) {
        currentMode = mode
        switch mode {
        case .photogrammetryOnly:
            startPhotogrammetryScanning()
        case .lidarOnly:
            startLidarScanning()
        case .hybridFusion:
            startHybridScanning()
        }
    }
    
    private func monitorSessionQuality(completion: @escaping (Float) -> Void) {
        // Monitor frame rate
        var frameCount = 0
        var lastFrameTime = CACurrentMediaTime()
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let currentTime = CACurrentMediaTime()
            let frameRate = Double(frameCount) / (currentTime - lastFrameTime)
            
            frameCount = 0
            lastFrameTime = currentTime
            
            // Calculate session quality based on frame rate and tracking state
            var quality: Float = min(Float(frameRate) / 30.0, 1.0) // Normalize to 30fps
            
            if let frame = self.currentFrame {
                // Reduce quality score based on tracking state
                switch frame.camera.trackingState {
                case .normal:
                    break // Keep current quality
                case .limited(let reason):
                    switch reason {
                    case .excessiveMotion:
                        quality *= 0.5
                    case .insufficientFeatures:
                        quality *= 0.7
                    case .initializing:
                        quality *= 0.3
                    @unknown default:
                        quality *= 0.5
                    }
                case .notAvailable:
                    quality = 0.0
                @unknown default:
                    quality *= 0.5
                }
            }
            
            completion(quality)
        }
    }
}

private struct QualityMetrics {
    var pointDensity: Float = 0
    var depthConsistency: Float = 0
    var normalConsistency: Float = 0
    var featureMatchQuality: Float = 0
    var imageQuality: Float = 0
    var coverageCompleteness: Float = 0
}

private struct FusionMetrics {
    var dataOverlap: Float = 0
    var geometricConsistency: Float = 0
    var scaleConsistency: Float = 0
}

struct FusionConfiguration {
    let lidarWeight: Float
    let photoWeight: Float
}

private func determineOptimalScanningMode() -> ScanningMode {
    let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    let hasTrueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    
    // Check environmental conditions
    let lightingQuality = assessLightingConditions()
    let motionStability = assessMotionStability()
    
    if hasLiDAR && lightingQuality > 0.7 && motionStability > 0.8 {
        return .lidar
    } else if hasTrueDepth && lightingQuality > 0.6 {
        return .hybrid
    } else {
        return .photogrammetry
    }
}

private func assessLightingConditions() -> Float {
    guard let frame = currentFrame,
          let lightEstimate = frame.lightEstimate else {
        return 0.0
    }
    return Float(lightEstimate.ambientIntensity) / 1000.0 // Normalize to 0-1
}

private func assessMotionStability() -> Float {
    guard let frame = currentFrame else {
        return 0.0
    }
    return frame.camera.trackingState == .normal ? 1.0 : 0.0
}

private func handleScanningFailure(_ error: Error) async {
    if fallbackAttempts < maxFallbackAttempts {
        fallbackAttempts += 1
        
        // Exponential backoff with jitter
        let baseDelay = pow(2.0, Double(fallbackAttempts))
        let jitter = Double.random(in: 0...0.5)
        let backoffDelay = baseDelay + jitter
        
        logger.info("Attempt \(fallbackAttempts): Retrying with \(backoffDelay)s delay")
        
        // Try alternative scanning strategies
        try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
        
        switch error {
        case ScanningError.insufficientLighting:
            await suggestLightingImprovements()
        case ScanningError.excessiveMotion:
            await enableMotionStabilization()
        case ScanningError.qualityBelowThreshold:
            await adjustQualitySettings()
        default:
            fallbackToNextMode()
        }
        
        await startScanningMode()
    } else {
        logger.error("Max retry attempts reached")
        throw ScanningError.processingFailed
    }
}

private func adjustQualitySettings() async {
    // Temporarily lower quality thresholds
    qualityThresholds.pointDensity *= 0.9
    qualityThresholds.surfaceCompleteness *= 0.95
    
    // Re-evaluate after 5 seconds
    try? await Task.sleep(nanoseconds: 5_000_000_000)
    resetQualityThresholds()
}

private func enableMotionStabilization() async {
    configuration.isTemporalStabilizationEnabled = true
    configuration.frameSemantics.insert(.smoothedSceneDepth)
}
