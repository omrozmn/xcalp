import Foundation
import simd

public class AdaptiveOctree {
    private class Node {
        var bounds: BoundingBox
        var points: [Point3D]
        var children: [Node]?
        var depth: Int
        
        init(bounds: BoundingBox, depth: Int) {
            self.bounds = bounds
            self.points = []
            self.depth = depth
        }
    }
    
    private let root: Node
    private let baseDepth: Int
    private let maxDepth: Int
    private let splitThreshold: Float
    
    public init(bounds: BoundingBox, baseDepth: Int, maxDepth: Int, splitThreshold: Float) {
        self.root = Node(bounds: bounds, depth: 0)
        self.baseDepth = baseDepth
        self.maxDepth = maxDepth
        self.splitThreshold = splitThreshold
    }
    
    public func insertWithRefinement(_ point: Point3D) async throws {
        try await insert(point, node: root)
    }
    
    private func insert(_ point: Point3D, node: Node) async throws {
        guard node.bounds.contains(point.position) else { return }
        
        if node.children == nil {
            // Add point to current node
            node.points.append(point)
            
            // Check if we need to split based on density and depth
            if shouldSplit(node) {
                try await split(node)
            }
        } else {
            // Recursively insert into appropriate child
            for child in node.children! {
                try await insert(point, node: child)
            }
        }
    }
    
    private func shouldSplit(_ node: Node) -> Bool {
        // Don't split if we're at max depth
        if node.depth >= maxDepth {
            return false
        }
        
        // Always split if we're below base depth and have points
        if node.depth < baseDepth && !node.points.isEmpty {
            return true
        }
        
        // Calculate point density
        let volume = node.bounds.volume
        let density = Float(node.points.count) / volume
        
        // Split if density exceeds threshold
        return density > splitThreshold
    }
    
    private func split(_ node: Node) async throws {
        let center = node.bounds.center
        let halfSize = node.bounds.size * 0.5
        
        // Create 8 child nodes
        node.children = []
        for x in 0..<2 {
            for y in 0..<2 {
                for z in 0..<2 {
                    let offset = SIMD3<Float>(
                        Float(x) - 0.5,
                        Float(y) - 0.5,
                        Float(z) - 0.5
                    ) * halfSize
                    
                    let childBounds = BoundingBox(
                        center: center + offset,
                        size: halfSize
                    )
                    
                    node.children?.append(Node(bounds: childBounds, depth: node.depth + 1))
                }
            }
        }
        
        // Redistribute points to children
        for point in node.points {
            for child in node.children! {
                if child.bounds.contains(point.position) {
                    child.points.append(point)
                    break
                }
            }
        }
        
        // Clear points from parent
        node.points.removeAll()
    }
    
    public func findNeighbors(of point: Point3D, radius: Float) async throws -> [Point3D] {
        var neighbors: [Point3D] = []
        try await findNeighborsRecursive(of: point, radius: radius, node: root, neighbors: &neighbors)
        return neighbors
    }
    
    private func findNeighborsRecursive(of point: Point3D, radius: Float, node: Node, neighbors: inout [Point3D]) async throws {
        // Skip if this node's bounds are too far
        if !node.bounds.intersectsSphere(center: point.position, radius: radius) {
            return
        }
        
        // Add points from this node if they're within radius
        for nodePoint in node.points {
            let distance = length(nodePoint.position - point.position)
            if distance <= radius && distance > 0 { // Exclude the point itself
                neighbors.append(nodePoint)
            }
        }
        
        // Recurse into children
        if let children = node.children {
            for child in children {
                try await findNeighborsRecursive(
                    of: point,
                    radius: radius,
                    node: child,
                    neighbors: &neighbors
                )
            }
        }
    }
}

public struct BoundingBox {
    let center: SIMD3<Float>
    let size: SIMD3<Float>
    
    var volume: Float {
        size.x * size.y * size.z
    }
    
    func contains(_ point: SIMD3<Float>) -> Bool {
        let diff = abs(point - center)
        let halfSize = size * 0.5
        return all(diff <= halfSize)
    }
    
    func intersectsSphere(center sphereCenter: SIMD3<Float>, radius: Float) -> Bool {
        let diff = abs(sphereCenter - center)
        let halfSize = size * 0.5
        
        // Find closest point on box to sphere center
        let closest = min(diff, halfSize)
        
        // If closest point is within radius, spheres intersects
        return length(closest) <= radius
    }
}