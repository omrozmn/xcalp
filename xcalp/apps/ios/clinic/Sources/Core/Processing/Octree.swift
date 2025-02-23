import Foundation
import simd

class Octree {
    private var root: OctreeNode
    private let maxDepth: Int
    
    init(maxDepth: Int = 8) {
        self.maxDepth = maxDepth
        self.root = OctreeNode(boundingBox: BoundingBox())
    }
    
    func insert(_ point: SIMD3<Float>) {
        root.insert(point, maxDepth: maxDepth)
    }
    
    func findKNearestNeighbors(to point: SIMD3<Float>, k: Int) -> [SIMD3<Float>] {
        var neighbors: [(point: SIMD3<Float>, distance: Float)] = []
        root.findKNearestNeighbors(to: point, k: k, neighbors: &neighbors)
        return neighbors.sorted { $0.distance < $1.distance }.map { $0.point }
    }
    
    func adaptNodes(_ condition: (OctreeNode) -> Bool) {
        root.adapt(condition)
    }
}

class OctreeNode {
    private var points: [SIMD3<Float>] = []
    private var children: [OctreeNode]?
    private let boundingBox: BoundingBox
    private let maxPointsPerNode = 8
    
    init(boundingBox: BoundingBox) {
        self.boundingBox = boundingBox
    }
    
    func insert(_ point: SIMD3<Float>, maxDepth: Int, currentDepth: Int = 0) {
        guard boundingBox.contains(point) else { return }
        
        if let children = children {
            let octant = getOctant(for: point)
            children[octant].insert(point, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        } else {
            points.append(point)
            
            if points.count > maxPointsPerNode && currentDepth < maxDepth {
                subdivide()
                
                // Redistribute points to children
                let currentPoints = points
                points.removeAll()
                for point in currentPoints {
                    insert(point, maxDepth: maxDepth, currentDepth: currentDepth)
                }
            }
        }
    }
    
    func findKNearestNeighbors(to query: SIMD3<Float>, k: Int, neighbors: inout [(point: SIMD3<Float>, distance: Float)]) {
        if let children = children {
            // Search children in order of distance to query point
            let childrenWithDistances = children.enumerated().map { (index, child) -> (index: Int, distance: Float) in
                let center = child.boundingBox.center
                return (index, distance(center, query))
            }
            
            for (index, _) in childrenWithDistances.sorted(by: { $0.distance < $1.distance }) {
                children[index].findKNearestNeighbors(to: query, k: k, neighbors: &neighbors)
            }
        } else {
            // Add points from this node
            for point in points {
                let dist = distance(point, query)
                
                if neighbors.count < k {
                    neighbors.append((point, dist))
                    neighbors.sort { $0.distance < $1.distance }
                } else if dist < neighbors.last!.distance {
                    neighbors.removeLast()
                    neighbors.append((point, dist))
                    neighbors.sort { $0.distance < $1.distance }
                }
            }
        }
    }
    
    func adapt(_ condition: (OctreeNode) -> Bool) {
        if condition(self) {
            subdivide()
        }
        
        children?.forEach { $0.adapt(condition) }
    }
    
    private func subdivide() {
        let center = boundingBox.center
        let halfSize = boundingBox.size * 0.5
        
        children = (0..<8).map { octant -> OctreeNode in
            let offset = SIMD3<Float>(
                Float(octant & 1),
                Float((octant >> 1) & 1),
                Float((octant >> 2) & 1)
            )
            let min = center + (offset - 1) * halfSize
            let max = center + offset * halfSize
            return OctreeNode(boundingBox: BoundingBox(min: min, max: max))
        }
    }
    
    private func getOctant(for point: SIMD3<Float>) -> Int {
        let center = boundingBox.center
        var octant = 0
        if point.x >= center.x { octant |= 1 }
        if point.y >= center.y { octant |= 2 }
        if point.z >= center.z { octant |= 4 }
        return octant
    }
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
}

private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    length(a - b)
}