import Foundation
import ARKit
import simd

public actor ScanCollisionDetector {
    public static let shared = ScanCollisionDetector()
    
    private let environmentAnalyzer: ScanEnvironmentAnalyzer
    private let analytics: AnalyticsService
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "CollisionDetection")
    
    private var activeScans: [UUID: CollisionContext] = [:]
    private var obstacleMap: ObstacleMap?
    private var safetyZones: [SafetyZone] = []
    
    private init(
        environmentAnalyzer: ScanEnvironmentAnalyzer = .shared,
        analytics: AnalyticsService = .shared
    ) {
        self.environmentAnalyzer = environmentAnalyzer
        self.analytics = analytics
    }
    
    public func startCollisionDetection(
        scanId: UUID,
        safetySettings: SafetySettings
    ) async throws -> CollisionContext {
        let context = CollisionContext(
            id: UUID(),
            scanId: scanId,
            settings: safetySettings,
            startTime: Date()
        )
        
        activeScans[context.id] = context
        
        // Initialize obstacle detection
        try await initializeObstacleDetection(context)
        
        analytics.track(
            event: .collisionDetectionStarted,
            properties: [
                "contextId": context.id.uuidString,
                "scanId": scanId.uuidString,
                "safetyLevel": safetySettings.level.rawValue
            ]
        )
        
        return context
    }
    
    public func updateScan(
        _ frame: ARFrame,
        context: CollisionContext
    ) async throws -> CollisionUpdate {
        guard activeScans[context.id] != nil else {
            throw CollisionError.contextNotFound
        }
        
        // Process new frame data
        let obstacles = try await detectObstacles(in: frame)
        
        // Update obstacle map
        updateObstacleMap(with: obstacles)
        
        // Check for potential collisions
        let collisions = checkCollisions(
            devicePosition: frame.camera.transform.columns.3.xyz,
            obstacles: obstacles
        )
        
        // Generate guidance if needed
        let guidance = generateGuidance(
            for: collisions,
            camera: frame.camera
        )
        
        let update = CollisionUpdate(
            obstacles: obstacles,
            collisions: collisions,
            guidance: guidance,
            timestamp: Date()
        )
        
        if !collisions.isEmpty {
            analytics.track(
                event: .collisionDetected,
                properties: [
                    "contextId": context.id.uuidString,
                    "collisionCount": collisions.count,
                    "nearestDistance": collisions.map(\.distance).min() ?? 0
                ]
            )
        }
        
        return update
    }
    
    public func defineSafetyZone(
        _ zone: SafetyZone,
        context: CollisionContext
    ) async {
        safetyZones.append(zone)
        
        analytics.track(
            event: .safetyZoneDefined,
            properties: [
                "contextId": context.id.uuidString,
                "zoneType": zone.type.rawValue,
                "zoneBounds": [
                    "minX": zone.bounds.min.x,
                    "minY": zone.bounds.min.y,
                    "minZ": zone.bounds.min.z,
                    "maxX": zone.bounds.max.x,
                    "maxY": zone.bounds.max.y,
                    "maxZ": zone.bounds.max.z
                ]
            ]
        )
    }
    
    public func endCollisionDetection(_ context: CollisionContext) async {
        activeScans.removeValue(forKey: context.id)
        
        analytics.track(
            event: .collisionDetectionEnded,
            properties: [
                "contextId": context.id.uuidString,
                "duration": Date().timeIntervalSince(context.startTime)
            ]
        )
    }
    
    private func initializeObstacleDetection(
        _ context: CollisionContext
    ) async throws {
        // Initialize obstacle map
        obstacleMap = ObstacleMap(resolution: context.settings.mapResolution)
        
        // Analyze environment for initial obstacles
        let analysis = try await environmentAnalyzer.beginAnalysis(
            scanId: context.scanId,
            requirements: .init(level: .professional)
        )
        
        let conditions = try await environmentAnalyzer.getCurrentConditions(analysis)
        
        // Initialize safety zones based on environment
        initializeSafetyZones(based: conditions)
    }
    
    private func detectObstacles(in frame: ARFrame) async throws -> [Obstacle] {
        var obstacles: [Obstacle] = []
        
        // Process point cloud
        if let points = frame.rawFeaturePoints {
            obstacles.append(contentsOf: detectPointCloudObstacles(points))
        }
        
        // Process plane anchors
        let planeObstacles = frame.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .map(convertPlaneToObstacle)
        
        obstacles.append(contentsOf: planeObstacles)
        
        return obstacles
    }
    
    private func detectPointCloudObstacles(_ points: ARPointCloud) -> [Obstacle] {
        let positions = Array(points.points)
        var obstacles: [Obstacle] = []
        
        // Cluster points into potential obstacles
        let clusters = clusterPoints(positions)
        
        for cluster in clusters {
            if let obstacle = createObstacle(from: cluster) {
                obstacles.append(obstacle)
            }
        }
        
        return obstacles
    }
    
    private func convertPlaneToObstacle(_ plane: ARPlaneAnchor) -> Obstacle {
        return Obstacle(
            id: UUID(),
            type: .plane,
            position: plane.center,
            extent: plane.extent,
            orientation: plane.transform.orientation,
            confidence: plane.confidence
        )
    }
    
    private func updateObstacleMap(with obstacles: [Obstacle]) {
        guard let map = obstacleMap else { return }
        
        for obstacle in obstacles {
            map.update(with: obstacle)
        }
        
        // Prune old obstacles
        map.prune(olderThan: 1.0) // 1 second
    }
    
    private func checkCollisions(
        devicePosition: SIMD3<Float>,
        obstacles: [Obstacle]
    ) -> [Collision] {
        var collisions: [Collision] = []
        
        // Check device position against obstacles
        for obstacle in obstacles {
            if let collision = checkCollision(
                position: devicePosition,
                against: obstacle
            ) {
                collisions.append(collision)
            }
        }
        
        // Check safety zone violations
        for zone in safetyZones {
            if let violation = checkSafetyZoneViolation(
                position: devicePosition,
                zone: zone
            ) {
                collisions.append(violation)
            }
        }
        
        return collisions
    }
    
    private func checkCollision(
        position: SIMD3<Float>,
        against obstacle: Obstacle
    ) -> Collision? {
        let distance = distance(position, obstacle.position)
        let threshold = obstacle.type.collisionThreshold
        
        guard distance < threshold else { return nil }
        
        return Collision(
            id: UUID(),
            obstacle: obstacle,
            position: position,
            distance: distance,
            severity: calculateCollisionSeverity(distance, threshold)
        )
    }
    
    private func checkSafetyZoneViolation(
        position: SIMD3<Float>,
        zone: SafetyZone
    ) -> Collision? {
        guard !zone.bounds.contains(position) else { return nil }
        
        let distance = zone.bounds.distance(to: position)
        
        return Collision(
            id: UUID(),
            obstacle: Obstacle(
                id: UUID(),
                type: .safetyZone,
                position: position,
                extent: .zero,
                orientation: .identity,
                confidence: 1.0
            ),
            position: position,
            distance: distance,
            severity: .high
        )
    }
    
    private func generateGuidance(
        for collisions: [Collision],
        camera: ARCamera
    ) -> MovementGuidance? {
        guard !collisions.isEmpty else { return nil }
        
        // Find most severe collision
        guard let worstCollision = collisions.max(by: { $0.severity < $1.severity }) else {
            return nil
        }
        
        // Calculate safe direction
        let safeDirection = calculateSafeDirection(
            from: camera.transform.columns.3.xyz,
            avoiding: worstCollision
        )
        
        return MovementGuidance(
            direction: safeDirection,
            distance: worstCollision.distance,
            urgency: worstCollision.severity
        )
    }
    
    private func calculateSafeDirection(
        from position: SIMD3<Float>,
        avoiding collision: Collision
    ) -> SIMD3<Float> {
        // Calculate direction away from obstacle
        var direction = normalize(position - collision.obstacle.position)
        
        // Check if direction violates any safety zones
        for zone in safetyZones {
            if !zone.bounds.contains(position + direction) {
                // Adjust direction to stay within safety zone
                direction = adjustDirectionForSafetyZone(
                    direction,
                    position: position,
                    zone: zone
                )
            }
        }
        
        return direction
    }
}

// MARK: - Types

extension ScanCollisionDetector {
    public struct CollisionContext {
        let id: UUID
        let scanId: UUID
        let settings: SafetySettings
        let startTime: Date
    }
    
    public struct SafetySettings {
        let level: SafetyLevel
        let mapResolution: Float
        let minimumSafeDistance: Float
        
        enum SafetyLevel: String {
            case standard
            case strict
            case medical
        }
    }
    
    public struct CollisionUpdate {
        public let obstacles: [Obstacle]
        public let collisions: [Collision]
        public let guidance: MovementGuidance?
        public let timestamp: Date
    }
    
    struct Obstacle {
        let id: UUID
        let type: ObstacleType
        let position: SIMD3<Float>
        let extent: SIMD3<Float>
        let orientation: simd_float4x4
        let confidence: Float
    }
    
    enum ObstacleType {
        case plane
        case pointCloud
        case safetyZone
        case dynamic
        
        var collisionThreshold: Float {
            switch self {
            case .plane: return 0.3
            case .pointCloud: return 0.2
            case .safetyZone: return 0.5
            case .dynamic: return 0.4
            }
        }
    }
    
    public struct Collision {
        public let id: UUID
        public let obstacle: Obstacle
        public let position: SIMD3<Float>
        public let distance: Float
        public let severity: Severity
        
        enum Severity: Int {
            case low = 0
            case medium = 1
            case high = 2
            case critical = 3
        }
    }
    
    public struct MovementGuidance {
        public let direction: SIMD3<Float>
        public let distance: Float
        public let urgency: Collision.Severity
    }
    
    struct SafetyZone {
        let type: ZoneType
        let bounds: BoundingBox
        
        enum ZoneType: String {
            case required
            case preferred
            case restricted
        }
    }
    
    class ObstacleMap {
        private var grid: [[[Obstacle]]]
        private let resolution: Float
        
        init(resolution: Float) {
            self.resolution = resolution
            self.grid = Array(
                repeating: Array(
                    repeating: Array(repeating: [], count: 100),
                    count: 100
                ),
                count: 100
            )
        }
        
        func update(with obstacle: Obstacle) {
            // Implementation for updating obstacle map
        }
        
        func prune(olderThan age: TimeInterval) {
            // Implementation for pruning old obstacles
        }
    }
    
    struct BoundingBox {
        let min: SIMD3<Float>
        let max: SIMD3<Float>
        
        func contains(_ point: SIMD3<Float>) -> Bool {
            point.x >= min.x && point.x <= max.x &&
            point.y >= min.y && point.y <= max.y &&
            point.z >= min.z && point.z <= max.z
        }
        
        func distance(to point: SIMD3<Float>) -> Float {
            // Calculate distance to nearest point on box
            let dx = max(min.x - point.x, 0, point.x - max.x)
            let dy = max(min.y - point.y, 0, point.y - max.y)
            let dz = max(min.z - point.z, 0, point.z - max.z)
            return sqrt(dx*dx + dy*dy + dz*dz)
        }
    }
    
    enum CollisionError: LocalizedError {
        case contextNotFound
        case initializationFailed
        
        var errorDescription: String? {
            switch self {
            case .contextNotFound:
                return "Collision detection context not found"
            case .initializationFailed:
                return "Failed to initialize collision detection"
            }
        }
    }
}

extension AnalyticsService.Event {
    static let collisionDetectionStarted = AnalyticsService.Event(name: "collision_detection_started")
    static let collisionDetectionEnded = AnalyticsService.Event(name: "collision_detection_ended")
    static let collisionDetected = AnalyticsService.Event(name: "collision_detected")
    static let safetyZoneDefined = AnalyticsService.Event(name: "safety_zone_defined")
}

extension simd_float4x4 {
    var orientation: simd_float4x4 {
        var result = self
        result.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        return result
    }
}