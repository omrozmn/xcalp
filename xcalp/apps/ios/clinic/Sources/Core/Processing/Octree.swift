import Foundation
import simd

/// Octree for efficient spatial partitioning and queries
final class Octree {
    private var root: OctreeNode
    private let maxDepth: Int
    private let minNodeSize: Float = 0.01 // 1cm minimum node size
    
    init(maxDepth: Int = 8) {
        self.maxDepth = maxDepth
        self.root = OctreeNode(boundingBox: BoundingBox())
    }
    
    func build(from mesh: MeshData) {
        // Reset and initialize root node bounds
        root = OctreeNode(boundingBox: mesh.metadata.boundingBox)
        
        // Insert all vertices with their data
        for (idx, vertex) in mesh.vertices.enumerated() {
            let point = OctreePoint(
                position: vertex,
                normal: mesh.normals[idx],
                confidence: mesh.confidence[idx]
            )
            root.insert(point, maxDepth: maxDepth)
        }
    }
    
    func findNeighbors(of point: SIMD3<Float>, within radius: Float) -> [OctreePoint] {
        var neighbors: [(point: OctreePoint, distance: Float)] = []
        root.findNeighbors(to: point, within: radius, neighbors: &neighbors)
        return neighbors.sorted { $0.distance < $1.distance }.map { $0.point }
    }
    
    func findKNearestNeighbors(to point: SIMD3<Float>, k: Int) -> [OctreePoint] {
        var neighbors: [(point: OctreePoint, distance: Float)] = []
        root.findKNearestNeighbors(to: point, k: k, neighbors: &neighbors)
        return neighbors.sorted { $0.distance < $1.distance }.map { $0.point }
    }
    
    func query(in boundingBox: BoundingBox) -> [OctreePoint] {
        var results: [OctreePoint] = []
        root.query(in: boundingBox, results: &results)
        return results
    }
}

/// Individual node in the octree
final class OctreeNode {
    private var points: [OctreePoint] = []
    private var children: [OctreeNode]?
    private let boundingBox: BoundingBox
    private let maxPointsPerNode = 8
    
    init(boundingBox: BoundingBox) {
        self.boundingBox = boundingBox
    }
    
    func insert(_ point: OctreePoint, maxDepth: Int, currentDepth: Int = 0) {
        guard contains(point.position) else { return }
        
        if let children = children {
            // Insert into appropriate child
            for child in children {
                if child.contains(point.position) {
                    child.insert(point, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                    return
                }
            }
        } else if points.count < maxPointsPerNode || currentDepth >= maxDepth {
            // Add to current node if under capacity or at max depth
            points.append(point)
        } else {
            // Split node and redistribute points
            subdivide()
            
            // Redistribute existing points
            let existingPoints = points
            points.removeAll()
            
            for existingPoint in existingPoints {
                insert(existingPoint, maxDepth: maxDepth, currentDepth: currentDepth)
            }
            
            // Insert new point
            insert(point, maxDepth: maxDepth, currentDepth: currentDepth)
        }
    }
    
    private func subdivide() {
        let center = boundingBox.center
        let halfSize = boundingBox.size * 0.5
        
        // Create 8 child nodes
        children = [
            // Bottom layer
            OctreeNode(boundingBox: BoundingBox(
                min: boundingBox.min,
                max: center)),
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(center.x, boundingBox.min.y, boundingBox.min.z),
                max: SIMD3<Float>(boundingBox.max.x, center.y, center.z))),
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(boundingBox.min.x, boundingBox.min.y, center.z),
                max: SIMD3<Float>(center.x, center.y, boundingBox.max.z))),
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(center.x, boundingBox.min.y, center.z),
                max: SIMD3<Float>(boundingBox.max.x, center.y, boundingBox.max.z))),
            
            // Top layer
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(boundingBox.min.x, center.y, boundingBox.min.z),
                max: SIMD3<Float>(center.x, boundingBox.max.y, center.z))),
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(center.x, center.y, boundingBox.min.z),
                max: SIMD3<Float>(boundingBox.max.x, boundingBox.max.y, center.z))),
            OctreeNode(boundingBox: BoundingBox(
                min: SIMD3<Float>(boundingBox.min.x, center.y, center.z),
                max: SIMD3<Float>(center.x, boundingBox.max.y, boundingBox.max.z))),
            OctreeNode(boundingBox: BoundingBox(
                min: center,
                max: boundingBox.max))
        ]
    }
    
    func findNeighbors(
        to point: SIMD3<Float>,
        within radius: Float,
        neighbors: inout [(point: OctreePoint, distance: Float)]
    ) {
        // Check if this node's bounding box is within search radius
        let closestPoint = boundingBox.closestPoint(to: point)
        let distanceToBox = distance(closestPoint, point)
        
        guard distanceToBox <= radius else { return }
        
        // Check points in this node
        for nodePoint in points {
            let dist = distance(nodePoint.position, point)
            if dist <= radius {
                neighbors.append((nodePoint, dist))
            }
        }
        
        // Recurse into children if they exist
        children?.forEach { child in
            child.findNeighbors(to: point, within: radius, neighbors: &neighbors)
        }
    }
    
    func findKNearestNeighbors(
        to point: SIMD3<Float>,
        k: Int,
        neighbors: inout [(point: OctreePoint, distance: Float)]
    ) {
        // If we have enough neighbors and this node is further than the current kth neighbor, skip
        if neighbors.count >= k,
           let maxDist = neighbors.map({ $0.distance }).max(),
           distance(boundingBox.closestPoint(to: point), point) > maxDist {
            return
        }
        
        // Add points from this node
        for nodePoint in points {
            let dist = distance(nodePoint.position, point)
            neighbors.append((nodePoint, dist))
        }
        
        // Sort and trim to k nearest
        neighbors.sort { $0.distance < $1.distance }
        if neighbors.count > k {
            neighbors.removeLast(neighbors.count - k)
        }
        
        // Recurse into children if they exist
        children?.forEach { child in
            child.findKNearestNeighbors(to: point, k: k, neighbors: &neighbors)
        }
    }
    
    private func contains(_ point: SIMD3<Float>) -> Bool {
        return point.x >= boundingBox.min.x && point.x <= boundingBox.max.x &&
               point.y >= boundingBox.min.y && point.y <= boundingBox.max.y &&
               point.z >= boundingBox.min.z && point.z <= boundingBox.max.z
    }
    
    func query(in queryBox: BoundingBox, results: inout [OctreePoint]) {
        // Check if this node's bounding box intersects with query box
        guard boundingBox.intersects(queryBox) else { return }
        
        // Add points that fall within query box
        points.forEach { point in
            if queryBox.contains(point.position) {
                results.append(point)
            }
        }
        
        // Recurse into children if they exist
        children?.forEach { child in
            child.query(in: queryBox, results: &results)
        }
    }
}

/// Point data stored in the octree
struct OctreePoint {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>?
    let confidence: Float
}

struct BoundingBox {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    
    init(min: SIMD3<Float> = .zero, max: SIMD3<Float> = .zero) {
        self.min = min
        self.max = max
    }
    
    var center: SIMD3<Float> {
        (min + max) * 0.5
    }
    
    var size: SIMD3<Float> {
        max - min
    }
    
    func contains(_ point: SIMD3<Float>) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }
    
    func intersects(_ other: BoundingBox) -> Bool {
        return max.x >= other.min.x && min.x <= other.max.x &&
               max.y >= other.min.y && min.y <= other.max.y &&
               max.z >= other.min.z && min.z <= other.max.z
    }
    
    func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            clamp(point.x, min: min.x, max: max.x),
            clamp(point.y, min: min.y, max: max.y),
            clamp(point.z, min: min.z, max: max.z)
        )
    }
}

private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
    return Swift.max(min, Swift.min(value, max))
}

private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    length(a - b)
}
