import Foundation
import simd

class OctreeNode {
    private let maxDepth = 8
    private let minPoints = 5
    
    var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    var center: SIMD3<Float>
    var points: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var children: [OctreeNode?] = Array(repeating: nil, count: 8)
    var value: Float = 0.0
    var depth: Int = 0
    
    init(boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>), depth: Int = 0) {
        self.boundingBox = boundingBox
        self.depth = depth
        self.center = (boundingBox.max + boundingBox.min) * 0.5
    }
    
    func insert(point: SIMD3<Float>, normal: SIMD3<Float>) {
        guard depth < maxDepth else {
            points.append(point)
            normals.append(normal)
            return
        }
        
        if points.count < minPoints {
            points.append(point)
            normals.append(normal)
            
            if points.count == minPoints {
                subdivide()
            }
        } else {
            let octant = getOctant(for: point)
            if children[octant] == nil {
                children[octant] = createChild(for: octant)
            }
            children[octant]?.insert(point: point, normal: normal)
        }
    }
    
    private func subdivide() {
        // Create child nodes and distribute points
        for (point, normal) in zip(points, normals) {
            let octant = getOctant(for: point)
            if children[octant] == nil {
                children[octant] = createChild(for: octant)
            }
            children[octant]?.insert(point: point, normal: normal)
        }
        
        // Clear points from this node as they've been distributed to children
        points.removeAll()
        normals.removeAll()
    }
    
    private func getOctant(for point: SIMD3<Float>) -> Int {
        var octant = 0
        if point.x >= center.x { octant |= 1 }
        if point.y >= center.y { octant |= 2 }
        if point.z >= center.z { octant |= 4 }
        return octant
    }
    
    private func createChild(for octant: Int) -> OctreeNode {
        var min = boundingBox.min
        var max = center
        
        if octant & 1 != 0 {
            min.x = center.x
        } else {
            max.x = center.x
        }
        
        if octant & 2 != 0 {
            min.y = center.y
        } else {
            max.y = center.y
        }
        
        if octant & 4 != 0 {
            min.z = center.z
        } else {
            max.z = center.z
        }
        
        return OctreeNode(boundingBox: (min, max), depth: depth + 1)
    }
    
    func updateValues(with solution: [Float]) {
        // Update the implicit function values from the Poisson equation solution
        value = solution[depth]
        
        for child in children.compactMap({ $0 }) {
            child.updateValues(with: solution)
        }
    }
    
    func evaluateImplicitFunction(at point: SIMD3<Float>) -> Float {
        // If this is a leaf node, return the value
        if children.allSatisfy({ $0 == nil }) {
            return value
        }
        
        // Otherwise, interpolate between child nodes
        let octant = getOctant(for: point)
        if let child = children[octant] {
            return child.evaluateImplicitFunction(at: point)
        }
        
        // If no child exists for this octant, interpolate from neighbors
        var sum: Float = 0
        var weight: Float = 0
        let h = length(boundingBox.max - boundingBox.min)
        
        for (i, child) in children.enumerated() {
            guard let child = child else { continue }
            let childCenter = child.center
            let dist = length(point - childCenter)
            let w = 1.0 / (dist + h * 0.1)
            sum += child.value * w
            weight += w
        }
        
        return weight > 0 ? sum / weight : value
    }
}