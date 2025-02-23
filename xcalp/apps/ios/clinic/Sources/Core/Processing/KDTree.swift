import Foundation
import simd

class KDTree {
    private var root: KDNode?
    
    init(points: [SIMD3<Float>]) {
        self.root = buildTree(points: points, depth: 0)
    }
    
    func nearest(to target: SIMD3<Float>) -> SIMD3<Float>? {
        guard let root = root else { return nil }
        var best = root
        var bestDistance = distance(target, root.point)
        
        searchNearest(node: root, target: target, best: &best, bestDistance: &bestDistance, depth: 0)
        return best.point
    }
    
    func kNearest(to target: SIMD3<Float>, k: Int) -> [SIMD3<Float>] {
        var nearestPoints = KNearestPoints(capacity: k)
        searchKNearest(node: root, target: target, nearest: &nearestPoints, depth: 0)
        return nearestPoints.points.map { $0.point }
    }
    
    private func buildTree(points: [SIMD3<Float>], depth: Int) -> KDNode? {
        guard !points.isEmpty else { return nil }
        
        let axis = depth % 3
        let sorted = points.sorted { 
            axis == 0 ? $0.x < $1.x : (axis == 1 ? $0.y < $1.y : $0.z < $1.z)
        }
        
        let medianIdx = sorted.count / 2
        let node = KDNode(point: sorted[medianIdx])
        
        node.left = buildTree(points: Array(sorted[..<medianIdx]), depth: depth + 1)
        node.right = buildTree(points: Array(sorted[(medianIdx + 1)...]), depth: depth + 1)
        
        return node
    }
    
    private func searchNearest(node: KDNode?, target: SIMD3<Float>, best: inout KDNode, bestDistance: inout Float, depth: Int) {
        guard let node = node else { return }
        
        let distance = self.distance(target, node.point)
        if distance < bestDistance {
            best = node
            bestDistance = distance
        }
        
        let axis = depth % 3
        let axisDelta = axis == 0 ? target.x - node.point.x :
                       (axis == 1 ? target.y - node.point.y : target.z - node.point.z)
        
        let nextBranch = axisDelta <= 0 ? node.left : node.right
        let otherBranch = axisDelta <= 0 ? node.right : node.left
        
        searchNearest(node: nextBranch, target: target, best: &best, bestDistance: &bestDistance, depth: depth + 1)
        
        if abs(axisDelta) < bestDistance {
            searchNearest(node: otherBranch, target: target, best: &best, bestDistance: &bestDistance, depth: depth + 1)
        }
    }
    
    private func searchKNearest(node: KDNode?, target: SIMD3<Float>, nearest: inout KNearestPoints, depth: Int) {
        guard let node = node else { return }
        
        let dist = distance(target, node.point)
        nearest.addPoint(PointDistance(point: node.point, distance: dist))
        
        let axis = depth % 3
        let axisDelta = axis == 0 ? target.x - node.point.x :
                       (axis == 1 ? target.y - node.point.y : target.z - node.point.z)
        
        let nextBranch = axisDelta <= 0 ? node.left : node.right
        let otherBranch = axisDelta <= 0 ? node.right : node.left
        
        searchKNearest(node: nextBranch, target: target, nearest: &nearest, depth: depth + 1)
        
        if abs(axisDelta) < nearest.maxDistance {
            searchKNearest(node: otherBranch, target: target, nearest: &nearest, depth: depth + 1)
        }
    }
}

private class KDNode {
    let point: SIMD3<Float>
    var left: KDNode?
    var right: KDNode?
    
    init(point: SIMD3<Float>) {
        self.point = point
    }
}

private struct PointDistance {
    let point: SIMD3<Float>
    let distance: Float
}

private struct KNearestPoints {
    private let capacity: Int
    var points: [PointDistance]
    
    init(capacity: Int) {
        self.capacity = capacity
        self.points = []
    }
    
    var maxDistance: Float {
        points.last?.distance ?? Float.infinity
    }
    
    mutating func addPoint(_ point: PointDistance) {
        if points.count < capacity {
            points.append(point)
            points.sort { $0.distance < $1.distance }
        } else if point.distance < points.last!.distance {
            points.removeLast()
            points.append(point)
            points.sort { $0.distance < $1.distance }
        }
    }
}

private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    length(a - b)
}