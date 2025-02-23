import Foundation
import Metal
import simd
import ARKit

enum ScanningMode {
    case lidarPrimary
    case photogrammetrySecondary
    case fusion
}

class DataFusionProcessor {
    private var lidarData: ARPointCloud?
    private var photogrammetryData: [PhotogrammetryPoint]?
    private let octree: Octree
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw FusionError.initializationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        self.octree = Octree(maxDepth: 8)
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
        return octree.findKNearestNeighbors(to: target, k: k)
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
        let totalConfidence = lidarConfidence + photoConfidence
        let lidarWeight = lidarConfidence / totalConfidence
        let photoWeight = photoConfidence / totalConfidence
        
        return lidarPoint * lidarWeight + photoPoint * photoWeight
    }
    
    private func getLidarConfidence(_ point: SIMD3<Float>) -> Float {
        // Implement LiDAR confidence calculation based on point characteristics
        // For now, return a default high confidence for LiDAR
        return 0.8
    }
    
    private func getPhotoConfidence(_ point: SIMD3<Float>) -> Float {
        // Implement photogrammetry confidence calculation
        // For now, return a default medium confidence
        return 0.6
    }
    
    private func requestRecalibration() {
        // Notify the system that recalibration is needed
        NotificationCenter.default.post(
            name: Notification.Name("RecalibrationNeeded"),
            object: nil
        )
    }
}