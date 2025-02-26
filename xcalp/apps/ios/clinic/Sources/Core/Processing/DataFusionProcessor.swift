import Foundation
import Metal
import MetalKit
import simd

enum ScanningMode: String {
    case lidarPrimary
    case photogrammetrySecondary
    case fusion
}

final class DataFusionProcessor {
    // MARK: - Properties
    
    private var fusionConfig: FusionConfiguration
    private let meshOptimizer: MeshOptimizer
    private let qualityThreshold: Float
    private var lidarData: PointCloud?
    private var photogrammetryData: [PhotogrammetryPoint]?
    private let octree: Octree
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // MARK: - Initialization
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw FusionError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.octree = Octree(maxDepth: 8)
        self.fusionConfig = FusionConfiguration(lidarWeight: 0.5, photoWeight: 0.5)
        self.meshOptimizer = try MeshOptimizer()
        self.qualityThreshold = ClinicalConstants.minimumFusionQuality
    }
    
    func configureFusion(_ config: FusionConfiguration) {
        self.fusionConfig = config
    }
    
    // Primary LiDAR scanning
    func processLidarData(_ pointCloud: ARPointCloud) -> Bool {
        self.lidarData = pointCloud
        
        // Convert LiDAR points to Octree format and insert
        for i in 0..<pointCloud.points.count {
            let point = pointCloud.points[i]
            octree.insert(point)
        }
        
        return true
    }
    
    // Secondary Photogrammetry processing
    func processPhotogrammetryData(_ points: [PhotogrammetryPoint]) -> Bool {
        self.photogrammetryData = points
        
        // Only use photogrammetry data if LiDAR data is missing or incomplete
        guard lidarData == nil || lidarData?.points.count ?? 0 < 1000 else {
            return false
        }
        
        // Insert photogrammetry points into Octree
        for point in points {
            octree.insert(point.position)
        }
        
        return true
    }
    
    // Fusion of both data sources
    func fuseData() -> [SIMD3<Float>] {
        var fusedPoints: [SIMD3<Float>] = []
        
        // Start with LiDAR data if available
        if let lidarPoints = lidarData?.points {
            fusedPoints.append(contentsOf: lidarPoints)
        }
        
        // Add photogrammetry data for areas where LiDAR data is sparse
        if let photoPoints = photogrammetryData {
            for point in photoPoints {
                // Check if we have enough LiDAR points in this area
                let neighbors = octree.findKNearestNeighbors(to: point.position, k: 5)
                if neighbors.count < 5 {
                    fusedPoints.append(point.position)
                }
            }
        }
        
        return fusedPoints
    }
    
    // Confidence scoring for point validation
    func getConfidenceScore(for point: SIMD3<Float>) -> Float {
        var score: Float = 0.0
        
        // Check LiDAR confidence if available
        if let lidarPoints = lidarData?.points {
            let nearestLidarPoints = findNearestPoints(point, in: lidarPoints, k: 3)
            score += calculateLidarConfidence(nearestLidarPoints)
        }
        
        // Check photogrammetry confidence if available
        if let photoPoints = photogrammetryData {
            let nearestPhotoPoints = photoPoints.sorted {
                distance($0.position, point) < distance($1.position, point)
            }.prefix(3)
            score += calculatePhotogrammetryConfidence(Array(nearestPhotoPoints))
        }
        
        return score
    }
    
    private func findNearestPoints(_ target: SIMD3<Float>, in points: [SIMD3<Float>], k: Int) -> [SIMD3<Float>] {
        octree.findKNearestNeighbors(to: target, k: k)
    }
    
    private func calculateLidarConfidence(_ points: [SIMD3<Float>]) -> Float {
        // Implement LiDAR confidence calculation based on point density and consistency
        // Returns a value between 0 and 1
        let density = Float(points.count) / 3.0 // Normalize by expected count
        return min(max(density, 0), 1)
    }
    
    private func calculatePhotogrammetryConfidence(_ points: [PhotogrammetryPoint]) -> Float {
        // Implement photogrammetry confidence calculation based on feature matching score
        // Returns a value between 0 and 1
        let averageConfidence = points.reduce(0) { $0 + $1.confidence } / Float(points.count)
        return min(max(averageConfidence, 0), 1)
    }
    
    func fuseData(lidar: PointCloud, photogrammetry: PointCloud, weights: FusionWeights) throws -> PointCloud {
        // Implement adaptive fusion based on confidence metrics
        let alignedClouds = try alignPointClouds(lidar, photogrammetry)
        
        // Apply TSDF fusion with confidence weighting
        return try performWeightedFusion(
            lidarCloud: alignedClouds.lidar,
            photoCloud: alignedClouds.photogrammetry,
            weights: weights
        )
    }
    
    private func alignPointClouds(_ lidarCloud: PointCloud, _ photoCloud: PointCloud) throws -> (lidar: PointCloud, photogrammetry: PointCloud) {
        // Implement ICP alignment with scale estimation
        let icp = ICPAlignment(maxIterations: 50, convergenceThreshold: 1e-6)
        let transform = try icp.align(source: photoCloud, target: lidarCloud)
        
        // Transform photogrammetry cloud to align with LiDAR
        let alignedPhoto = photoCloud.applying(transform)
        
        return (lidarCloud, alignedPhoto)
    }
    
    private func performWeightedFusion(
        lidarCloud: PointCloud,
        photoCloud: PointCloud,
        weights: FusionWeights
    ) throws -> PointCloud {
        var fusedPoints: [WeightedPoint] = []
        
        // Create spatial index for efficient nearest neighbor search
        let photoIndex = try SpatialIndex(points: photoCloud.points)
        
        // For each LiDAR point, find corresponding photogrammetry points
        for lidarPoint in lidarCloud.points {
            let nearestPhoto = try photoIndex.findNearest(to: lidarPoint.position, maxDistance: 0.01)
            
            if let photoPoint = nearestPhoto {
                // Calculate weighted position based on confidence
                let lidarWeight = weights.lidar * lidarPoint.confidence
                let photoWeight = weights.photogrammetry * photoPoint.confidence
                let totalWeight = lidarWeight + photoWeight
                
                let weightedPosition = (lidarPoint.position * lidarWeight + 
                                      photoPoint.position * photoWeight) / totalWeight
                
                fusedPoints.append(WeightedPoint(
                    position: weightedPosition,
                    confidence: (lidarPoint.confidence + photoPoint.confidence) / 2,
                    normal: normalizeWeightedNormal(
                        n1: lidarPoint.normal, w1: lidarWeight,
                        n2: photoPoint.normal, w2: photoWeight
                    )
                ))
            } else {
                // Keep LiDAR point if no photogrammetry correspondence
                fusedPoints.append(WeightedPoint(
                    position: lidarPoint.position,
                    confidence: lidarPoint.confidence,
                    normal: lidarPoint.normal
                ))
            }
        }
        
        return PointCloud(points: fusedPoints)
    }
    
    // MARK: - Core Fusion Logic

    func fuseData(lidarData: ARMeshGeometry, photoData: PhotogrammetryData) throws -> FusedScanResult {
        let perfID = PerformanceMonitor.shared.startMeasuring("dataFusion", category: "processing")
        defer { PerformanceMonitor.shared.endMeasuring("dataFusion", signpostID: perfID, category: "processing") }
        
        // Step 1: Align photogrammetry data with LiDAR mesh
        let alignedPhotoData = try alignPhotogrammetryData(photoData, with: lidarData)
        
        // Step 2: Calculate confidence scores
        let lidarConfidence = calculateLidarConfidence(lidarData)
        let photoConfidence = calculatePhotogrammetryConfidence(alignedPhotoData)
        
        // Step 3: Determine adaptive weights based on confidence scores
        let weights = FusionWeights.adaptive(
            lidarConfidence: lidarConfidence,
            photoConfidence: photoConfidence
        )
        
        // Step 4: Fuse point clouds with weighted confidence
        let fusedPointCloud = try fuseLidarAndPhoto(
            lidarMesh: lidarData,
            photoPoints: alignedPhotoData.points,
            weights: weights
        )
        
        // Step 5: Optimize fused mesh
        let optimizedMesh = try meshOptimizer.optimizeMesh(fusedPointCloud)
        
        // Step 6: Validate fusion quality
        let quality = validateFusion(optimizedMesh)
        guard quality >= qualityThreshold else {
            throw FusionError.qualityBelowThreshold(quality)
        }
        
        // Step 7: Generate confidence map
        let confidenceMap = generateConfidenceMap(
            mesh: optimizedMesh,
            lidarConfidence: weights.lidar,
            photoConfidence: weights.photogrammetry
        )
        
        return FusedScanResult(
            mesh: optimizedMesh,
            confidence: quality,
            confidenceMap: confidenceMap,
            metadata: generateFusionMetadata()
        )
    }

    private func alignPhotogrammetryData(_ photoData: PhotogrammetryData, with lidarMesh: ARMeshGeometry) throws -> AlignedPhotoData {
        // Implement ICP (Iterative Closest Point) alignment
        var currentTransform = matrix_identity_float4x4
        let maxIterations = 50
        let convergenceThreshold: Float = 1e-6
        var previousError: Float = .infinity
        
        let photoPoints = photoData.features.map { $0.worldPosition }
        let lidarPoints = extractLidarPoints(from: lidarMesh)
        
        for iteration in 0..<maxIterations {
            // Find closest points between sets
            let correspondences = findCorrespondences(
                source: photoPoints,
                target: lidarPoints
            )
            
            // Calculate optimal transformation
            let transform = calculateOptimalTransform(
                source: correspondences.source,
                target: correspondences.target
            )
            
            // Update cumulative transformation
            currentTransform = transform * currentTransform
            
            // Calculate error metric
            let currentError = calculateAlignmentError(correspondences)
            
            // Check for convergence
            let errorDelta = abs(previousError - currentError)
            if errorDelta < convergenceThreshold {
                break
            }
            
            previousError = currentError
        }
        
        // Transform photogrammetry points to aligned position
        let alignedPoints = photoPoints.map { transformPoint($0, by: currentTransform) }
        
        // Calculate confidence based on alignment quality
        let alignmentConfidence = calculateAlignmentConfidence(
            error: previousError,
            correspondenceCount: photoPoints.count
        )
        
        return AlignedPhotoData(
            points: alignedPoints,
            transform: currentTransform,
            confidence: alignmentConfidence
        )
    }
    
    private func fuseLidarAndPhoto(
        lidarMesh: ARMeshGeometry,
        photoPoints: [SIMD3<Float>],
        weights: FusionWeights
    ) -> ARMeshGeometry {
        var fusedVertices: [SIMD3<Float>] = []
        var fusedNormals: [SIMD3<Float>] = []
        
        // Extract LiDAR data
        let lidarVertices = Array(lidarMesh.vertices)
        let lidarNormals = Array(lidarMesh.normals)
        
        // Build spatial index for fast neighbor lookups
        let spatialIndex = SpatialIndex(points: photoPoints)
        
        // Process each LiDAR vertex
        for i in 0..<lidarVertices.count {
            let lidarVertex = lidarVertices[i]
            let lidarNormal = lidarNormals[i]
            
            // Find nearby photogrammetry points
            let neighbors = spatialIndex.findNeighbors(
                for: lidarVertex,
                radius: 0.01 // 1cm radius
            )
            
            if !neighbors.isEmpty {
                // Calculate weighted average position
                let photoWeight = weights.photogrammetry
                let lidarWeight = weights.lidar
                let totalWeight = photoWeight + lidarWeight
                
                let weightedPos = neighbors.reduce(lidarVertex * lidarWeight) {
                    $0 + $1 * (photoWeight / Float(neighbors.count))
                } / totalWeight
                
                let weightedNormal = normalize(
                    lidarNormal * lidarWeight +
                    photoNormal * photoWeight
                )
                
                fusedVertices.append(weightedPos)
                fusedNormals.append(weightedNormal)
            } else {
                // Keep original LiDAR data where no photogrammetry data exists
                fusedVertices.append(lidarVertex)
                fusedNormals.append(lidarNormal)
            }
        }
        
        // Create new mesh geometry with fused data
        return createMeshGeometry(
            vertices: fusedVertices,
            normals: fusedNormals,
            faces: Array(lidarMesh.faces)
        )
    }
    
    private func validateFusion(_ mesh: OptimizedMesh) -> Float {
        // Calculate geometric consistency (40%)
        let geometricScore = calculateGeometricConsistency(mesh.vertices, mesh.normals)
        
        // Calculate feature preservation (40%)
        let featureScore = calculateFeaturePreservation(
            vertices: mesh.vertices,
            normals: mesh.normals,
            features: mesh.features
        )
        
        // Calculate surface smoothness (20%)
        let smoothnessScore = calculateSurfaceSmoothness(
            vertices: mesh.vertices,
            normals: mesh.normals,
            faces: mesh.faces
        )
        
        // Calculate final weighted score
        let finalScore = geometricScore * 0.4 +
                        featureScore * 0.4 +
                        smoothnessScore * 0.2
        
        logger.info("""
            Fusion quality metrics:
            - Geometric Consistency: \(geometricScore)
            - Feature Preservation: \(featureScore)
            - Surface Smoothness: \(smoothnessScore)
            - Final Score: \(finalScore)
            """)
        
        return finalScore
    }

    private func calculateGeometricConsistency(_ vertices: [SIMD3<Float>], _ normals: [SIMD3<Float>]) -> Float {
        var consistency: Float = 0
        let spatialIndex = SpatialIndex(points: vertices)
        
        for (idx, vertex) in vertices.enumerated() {
            let normal = normals[idx]
            let neighbors = spatialIndex.findNeighbors(for: vertex, radius: 0.01)
            
            if !neighbors.isEmpty {
                let neighborNormals = neighbors.map { neighborIdx in
                    normals[neighborIdx]
                }
                
                let averageNormal = normalize(neighborNormals.reduce(.zero, +))
                consistency += abs(dot(normal, averageNormal))
            }
        }
        
        return vertices.isEmpty ? 0 : consistency / Float(vertices.count)
    }

    private func calculateFeaturePreservation(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        features: [MeshFeature]
    ) -> Float {
        var preservation: Float = 0
        
        for feature in features {
            let featureNormal = normals[feature.vertexIndex]
            let neighbors = findNeighborVertices(
                vertices[feature.vertexIndex],
                vertices,
                radius: 0.01
            )
            
            if !neighbors.isEmpty {
                let curvature = calculateLocalCurvature(
                    vertices[feature.vertexIndex],
                    featureNormal,
                    neighbors
                )
                
                // Higher preservation score for maintained features
                preservation += 1.0 - curvature
            }
        }
        
        return features.isEmpty ? 1.0 : preservation / Float(features.count)
    }

    private func calculateSurfaceSmoothness(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        faces: [Int32]
    ) -> Float {
        var smoothness: Float = 0
        
        for i in stride(from: 0, to: faces.count, by: 3) {
            let v1 = vertices[Int(faces[i])]
            let v2 = vertices[Int(faces[i + 1])]
            let v3 = vertices[Int(faces[i + 2])]
            
            let n1 = normals[Int(faces[i])]
            let n2 = normals[Int(faces[i + 1])]
            let n3 = normals[Int(faces[i + 2])]
            
            // Calculate normal variation within triangle
            let normalVariation = (dot(n1, n2) + dot(n2, n3) + dot(n3, n1)) / 3.0
            
            // Calculate edge length variation
            let e1 = length(v2 - v1)
            let e2 = length(v3 - v2)
            let e3 = length(v1 - v3)
            let avgEdge = (e1 + e2 + e3) / 3.0
            let edgeVariation = 1.0 - (abs(e1 - avgEdge) + abs(e2 - avgEdge) + abs(e3 - avgEdge)) / (3.0 * avgEdge)
            
            smoothness += (normalVariation + edgeVariation) * 0.5
        }
        
        return faces.isEmpty ? 0 : smoothness / Float(faces.count / 3)
    }
    
    private func generateConfidenceMap(
        mesh: OptimizedMesh,
        lidarConfidence: Float,
        photoConfidence: Float
    ) -> ConfidenceMap {
        var vertexConfidences: [Float] = []
        
        for (vertex, normal) in zip(mesh.vertices, mesh.normals) {
            // Calculate base confidence from input sources
            var confidence = lidarConfidence
            
            // Adjust for geometric factors
            let curvature = calculateLocalCurvature(vertex: vertex, normal: normal, mesh: mesh)
            confidence *= (1.0 - curvature) // Reduce confidence in high-curvature regions
            
            // Adjust for feature preservation
            if let featureIndex = mesh.featureVertices.firstIndex(where: { length($0 - vertex) < 0.001 }) {
                confidence *= mesh.featureStrengths[featureIndex]
            }
            
            vertexConfidences.append(confidence)
        }
        
        return ConfidenceMap(
            vertexConfidences: vertexConfidences,
            averageConfidence: vertexConfidences.reduce(0, +) / Float(vertexConfidences.count)
        )
    }
    
    // Helper methods
    private func calculateLocalCurvature(
        vertex: SIMD3<Float>,
        normal: SIMD3<Float>,
        mesh: OptimizedMesh
    ) -> Float {
        // Find neighboring vertices
        let neighbors = findNeighborVertices(for: vertex, in: mesh)
        
        // Calculate mean curvature using laplacian operator
        var curvature: Float = 0
        
        for neighbor in neighbors {
            let edge = neighbor - vertex
            let angle = acos(dot(normal, normalize(edge)))
            curvature += angle
        }
        
        return neighbors.isEmpty ? 0 : curvature / Float(neighbors.count)
    }
    
    private func calculateGeometricConsistency(_ mesh: OptimizedMesh) -> Float {
        var consistency: Float = 0
        
        for i in 0..<mesh.vertices.count {
            let normal = mesh.normals[i]
            let neighbors = findNeighborVertices(for: mesh.vertices[i], in: mesh)
            
            if !neighbors.isEmpty {
                let neighborNormals = neighbors.map { neighbor -> SIMD3<Float> in
                    let edge = normalize(neighbor - mesh.vertices[i])
                    return normalize(cross(edge, normal))
                }
                
                let averageNormal = normalize(neighborNormals.reduce(.zero, +))
                consistency += abs(dot(normal, averageNormal))
            }
        }
        
        return mesh.vertices.isEmpty ? 0 : consistency / Float(mesh.vertices.count)
    }
    
    private func generateFusionMetadata() -> FusionMetadata {
        FusionMetadata(
            timestamp: Date(),
            fusionConfig: fusionConfig,
            processingTime: CACurrentMediaTime(),
            memoryUsage: ProcessInfo.processInfo.physicalMemory
        )
    }
    
    private func calculateLidarConfidence(_ lidarData: ARMeshGeometry) -> Float {
        let vertices = Array(lidarData.vertices)
        let normals = Array(lidarData.normals)
        
        // Calculate point cloud density score (30%)
        let density = calculateLocalDensity(vertices)
        let densityScore = min(density / 1000.0, 1.0) * 0.3
        
        // Calculate normal consistency score (40%)
        let normalConsistency = calculateNormalConsistency(vertices, normals)
        let normalScore = normalConsistency * 0.4
        
        // Calculate geometric stability score (30%)
        let stability = calculateGeometricStability(vertices, Array(lidarData.faces))
        let stabilityScore = stability * 0.3
        
        return densityScore + normalScore + stabilityScore
    }

    private func calculatePhotogrammetryConfidence(_ photoData: AlignedPhotoData) -> Float {
        // Calculate feature matching score (40%)
        let featureScore = photoData.points.map { $0.matchConfidence }.reduce(0, +) / Float(photoData.points.count) * 0.4
        
        // Calculate reprojection error score (30%)
        let reprojectionScore = (1.0 - calculateReprojectionError(photoData)) * 0.3
        
        // Calculate coverage score (30%)
        let coverageScore = calculateCoverageScore(photoData.points) * 0.3
        
        return featureScore + reprojectionScore + coverageScore
    }

    private func calculateNormalConsistency(_ vertices: [SIMD3<Float>], _ normals: [SIMD3<Float>]) -> Float {
        var consistencyScore: Float = 0
        
        for i in 0..<vertices.count {
            let neighbors = findNeighborVertices(vertices[i], vertices, radius: 0.01)
            if neighbors.isEmpty { continue }
            
            let neighborNormals = neighbors.compactMap { neighbor -> SIMD3<Float>? in
                guard let idx = vertices.firstIndex(where: { length($0 - neighbor) < Float.ulpOfOne }) else { return nil }
                return normals[idx]
            }
            
            let normalVariation = calculateNormalVariation(normals[i], neighborNormals)
            consistencyScore += 1 - normalVariation
        }
        
        return consistencyScore / Float(vertices.count)
    }

    private func calculateGeometricStability(_ vertices: [SIMD3<Float>], _ faces: [Int32]) -> Float {
        var stabilityScore: Float = 0
        let triangleCount = faces.count / 3
        
        for i in stride(from: 0, to: faces.count, by: 3) {
            let v1 = vertices[Int(faces[i])]
            let v2 = vertices[Int(faces[i + 1])]
            let v3 = vertices[Int(faces[i + 2])]
            
            // Calculate triangle quality metrics
            let edgeLengths = [
                length(v2 - v1),
                length(v3 - v2),
                length(v1 - v3)
            ]
            
            // Calculate aspect ratio
            let s = edgeLengths.reduce(0, +) * 0.5
            let area = sqrt(s * (s - edgeLengths[0]) * (s - edgeLengths[1]) * (s - edgeLengths[2]))
            let aspectRatio = (edgeLengths[0] * edgeLengths[1] * edgeLengths[2]) / (8 * area * area)
            
            stabilityScore += 1 / aspectRatio
        }
        
        return stabilityScore / Float(triangleCount)
    }

    private func calculateReprojectionError(_ photoData: AlignedPhotoData) -> Float {
        // Calculate average reprojection error across all matched features
        let errors = photoData.points.compactMap { point -> Float? in
            guard let projected = projectPoint(point.position) else { return nil }
            return length(projected - point.imagePoint)
        }
        
        let meanError = errors.reduce(0, +) / Float(errors.count)
        return min(meanError / 10.0, 1.0) // Normalize to [0,1], assuming 10px is max acceptable error
    }
}

struct FusionWeights {
    let lidar: Float
    let photogrammetry: Float
    
    static func adaptive(lidarConfidence: Float, photoConfidence: Float) -> FusionWeights {
        let total = lidarConfidence + photoConfidence
        return FusionWeights(
            lidar: lidarConfidence / total,
            photogrammetry: photoConfidence / total
        )
    }
}

enum FusionError: Error {
    case initializationFailed
    case alignmentFailed
    case fusionFailed
    case qualityBelowThreshold(Float)
}

// Supporting struct for photogrammetry data
struct PhotogrammetryPoint {
    let position: SIMD3<Float>
    let confidence: Float // 0 to 1, representing feature matching confidence
    let color: simd_float3? // Optional RGB color data
}

extension DataFusionProcessor {
    private let fusionValidator = FusionValidator()
    private var currentStrategy: ScanningStrategy = .lidarOnly
    
    func processAndValidate(lidarPoints: [SIMD3<Float>]?, photoPoints: [SIMD3<Float>]?, boundingBox: BoundingBox) -> ScanningStrategy {
        // Validate available data
        let validationResult = fusionValidator.validateFusion(
            lidarPoints: lidarPoints ?? [],
            photoPoints: photoPoints ?? [],
            boundingBox: boundingBox
        )
        
        // Update strategy based on validation
        currentStrategy = validationResult.recommendedStrategy
        
        switch currentStrategy {
        case .fusion:
            performDataFusion(lidarPoints: lidarPoints!, photoPoints: photoPoints!)
        case .lidarOnly:
            processLidarData(lidarPoints!)
        case .photogrammetryOnly:
            processPhotogrammetryData(photoPoints!)
        case .needsRecalibration:
            requestRecalibration()
        }
        
        return currentStrategy
    }
    
    private func performDataFusion(lidarPoints: [SIMD3<Float>], photoPoints: [SIMD3<Float>]) {
        // Align data using ICP
        let icpAlignment = ICPAlignment()
        let (transform, _) = icpAlignment.align(source: photoPoints, target: lidarPoints)
        
        // Transform photogrammetry points to align with LiDAR
        let alignedPhotoPoints = photoPoints.map { point in
            transformPoint(point, transform: transform)
        }
        
        // Merge datasets with confidence weighting
        mergeFusedData(lidarPoints: lidarPoints, photoPoints: alignedPhotoPoints)
    }
    
    private func transformPoint(_ point: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float> {
        let homogeneous = SIMD4<Float>(point.x, point.y, point.z, 1)
        let transformed = matrix_multiply(transform, homogeneous)
        return SIMD3<Float>(transformed.x / transformed.w,
                           transformed.y / transformed.w,
                           transformed.z / transformed.w)
    }
    
    private func mergeFusedData(lidarPoints: [SIMD3<Float>], photoPoints: [SIMD3<Float>]) {
        // Create spatial index for efficient nearest neighbor queries
        let kdTree = KDTree(points: lidarPoints)
        
        // Combine points with confidence-based weighting
        for photoPoint in photoPoints {
            if let nearestLidarPoint = kdTree.nearest(to: photoPoint) {
                let distance = length(photoPoint - nearestLidarPoint)
                
                if distance <= ScanningQualityThresholds.maximumFusionDistance {
                    // Weight points based on confidence scores
                    let fusedPoint = weightedFusion(
                        lidarPoint: nearestLidarPoint,
                        photoPoint: photoPoint,
                        lidarConfidence: getLidarConfidence(nearestLidarPoint),
                        photoConfidence: getPhotoConfidence(photoPoint)
                    )
                    octree.insert(fusedPoint)
                } else {
                    // Add photogrammetry point if no nearby LiDAR point
                    octree.insert(photoPoint)
                }
            }
        }
    }
    
    private func weightedFusion(
        lidarPoint: SIMD3<Float>,
        photoPoint: SIMD3<Float>,
        lidarConfidence: Float,
        photoConfidence: Float
    ) -> SIMD3<Float> {
        let environmentalFactor = assessEnvironmentalConditions()
        let adaptiveLidarWeight = lidarConfidence * environmentalFactor
        let adaptivePhotoWeight = photoConfidence * (1 - environmentalFactor)
        
        let totalWeight = adaptiveLidarWeight + adaptivePhotoWeight
        guard totalWeight > 0 else { return lidarPoint }
        
        let lidarWeight = adaptiveLidarWeight / totalWeight
        let photoWeight = adaptivePhotoWeight / totalWeight
        
        return lidarPoint * lidarWeight + photoPoint * photoWeight
    }

    private func assessEnvironmentalConditions() -> Float {
        // Prefer LiDAR in good lighting conditions
        if let lightEstimate = currentFrame?.lightEstimate {
            let normalizedLighting = Float(lightEstimate.ambientIntensity) / 1000.0
            return min(max(normalizedLighting, 0.3), 0.7) // Keep between 0.3-0.7
        }
        return 0.5 // Default to equal weighting
    }
    
    private func getLidarConfidence(_ point: SIMD3<Float>) -> Float {
        var confidence: Float = 0.0
        
        // Point density contribution (40%)
        let localDensity = calculateLocalDensity(around: point)
        let densityScore = normalize(
            localDensity,
            min: ScanningConfiguration.QualityThresholds.minPointDensity,
            max: ScanningConfiguration.QualityThresholds.maxPointDensity
        ) * 0.4
        
        // Depth consistency contribution (30%)
        let depthConsistency = calculateDepthConsistency(at: point)
        let depthScore = depthConsistency * 0.3
        
        // Surface normal stability contribution (30%)
        let normalStability = calculateNormalStability(at: point)
        let normalScore = normalStability * 0.3
        
        confidence = densityScore + depthScore + normalScore
        return min(max(confidence, 0), 1)
    }
    
    private func getPhotoConfidence(_ point: SIMD3<Float>) -> Float {
        var confidence: Float = 0.0
        
        // Feature matching score contribution (40%)
        let featureScore = calculateFeatureMatchingScore(at: point)
        let matchScore = featureScore * 0.4
        
        // Image quality contribution (30%)
        let imageQuality = calculateImageQuality(at: point)
        let qualityScore = imageQuality * 0.3
        
        // Geometric consistency contribution (30%)
        let geometricConsistency = calculateGeometricConsistency(at: point)
        let geometryScore = geometricConsistency * 0.3
        
        confidence = matchScore + qualityScore + geometryScore
        return min(max(confidence, 0), 1)
    }
    
    private func calculateLocalDensity(around point: SIMD3<Float>, radius: Float = 0.05) -> Float {
        let neighbors = octree.findNeighbors(within: radius, of: point)
        let volume = (4.0 / 3.0) * .pi * pow(radius, 3)
        
        return Float(neighbors.count) / volume
    }
    
    private func calculateDepthConsistency(at point: SIMD3<Float>) -> Float {
        let neighbors = octree.findKNearestNeighbors(to: point, k: 8)
        let depths = neighbors.map { length($0 - point) }
        return 1.0 - (standardDeviation(depths) / mean(depths))
    }
    
    private func calculateNormalStability(at point: SIMD3<Float>) -> Float {
        let neighbors = octree.findKNearestNeighbors(to: point, k: 8)
        let normal = estimateNormal(point, neighbors)
        let neighborNormals = neighbors.map { estimateNormal($0, octree.findKNearestNeighbors(to: $0, k: 8)) }
        
        let normalDeviations = neighborNormals.map { abs(dot(normal, $0)) }
        return mean(normalDeviations)
    }
    
    private func calculateFeatureMatchingScore(at point: SIMD3<Float>) -> Float {
        guard let features = currentFrame?.features else { return 0.0 }
        let projectedPoint = projectPoint(point)
        
        let nearestFeature = features.min(by: { f1, f2 in
            distance(projectedPoint, f1.imagePoint) < distance(projectedPoint, f2.imagePoint)
        })
        
        return nearestFeature?.matchConfidence ?? 0.0
    }
    
    private func calculateImageQuality(at point: SIMD3<Float>) -> Float {
        guard let frame = currentFrame else { return 0.0 }
        let projectedPoint = projectPoint(point)
        
        // Check if point projects into valid image region
        guard frame.contains(projectedPoint) else { return 0.0 }
        
        return calculateLocalContrast(at: projectedPoint, in: frame) * 
               calculateLocalSharpness(at: projectedPoint, in: frame)
    }
    
    private func calculateGeometricConsistency(at point: SIMD3<Float>) -> Float {
        guard let neighbors = try? octree.findKNearestNeighbors(to: point, k: 8) else {
            return 0.0
        }
        
        let localPlaneFit = fitPlane(to: neighbors)
        return 1.0 - abs(dot(normalize(point - localPlaneFit.center), localPlaneFit.normal))
    }
    
    // Helper functions
    private func normalize(_ value: Float, min: Float, max: Float) -> Float {
        return (value - min) / (max - min)
    }
    
    private func mean(_ values: [Float]) -> Float {
        return values.reduce(0, +) / Float(values.count)
    }
    
    private func standardDeviation(_ values: [Float]) -> Float {
        let avg = mean(values)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }
    
    private func requestRecalibration() {
        // Notify the system that recalibration is needed
        NotificationCenter.default.post(
            name: Notification.Name("RecalibrationNeeded"),
            object: nil
        )
    }
}

// Supporting types
struct AlignedPhotoData {
    let points: [SIMD3<Float>]
    let transform: simd_float4x4
    let confidence: Float
}

struct FusedScanResult {
    let mesh: OptimizedMesh
    let confidence: Float
    let confidenceMap: ConfidenceMap
    let metadata: FusionMetadata
}

struct ConfidenceMap {
    let vertexConfidences: [Float]
    let averageConfidence: Float
}

struct FusionMetadata {
    let timestamp: Date
    let fusionConfig: FusionConfiguration
    let processingTime: CFTimeInterval
    let memoryUsage: UInt64
}

enum FusionError: Error {
    case alignmentFailed
    case insufficientCorrespondences
    case qualityBelowThreshold(Float)
}

// Spatial indexing for efficient neighbor searches
private class SpatialIndex {
    private let points: [SIMD3<Float>]
    private let gridSize: Float = 0.1 // 10cm grid cells
    private var grid: [SIMD3<Int>: [Int]] = [:]
    
    init(points: [SIMD3<Float>]) {
        self.points = points
        buildIndex()
    }
    
    private func buildIndex() {
        for (i, point) in points.enumerated() {
            let cell = gridCell(for: point)
            grid[cell, default: []].append(i)
        }
    }
    
    private func gridCell(for point: SIMD3<Float>) -> SIMD3<Int> {
        SIMD3<Int>(
            Int(floor(point.x / gridSize)),
            Int(floor(point.y / gridSize)),
            Int(floor(point.z / gridSize))
        )
    }
    
    func findNeighbors(for point: SIMD3<Float>, radius: Float) -> [SIMD3<Float>] {
        let cell = gridCell(for: point)
        let cellRadius = Int(ceil(radius / gridSize))
        var neighbors: [SIMD3<Float>] = []
        
        // Search neighboring cells
        for x in -cellRadius...cellRadius {
            for y in -cellRadius...cellRadius {
                for z in -cellRadius...cellRadius {
                    let neighborCell = cell &+ SIMD3<Int>(x, y, z)
                    if let indices = grid[neighborCell] {
                        for index in indices {
                            let neighbor = points[index]
                            if length(neighbor - point) <= radius {
                                neighbors.append(neighbor)
                            }
                        }
                    }
                }
            }
        }
        
        return neighbors
    }
}
