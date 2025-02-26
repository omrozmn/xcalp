import Foundation
import Metal
import simd
import os.log

final class FeatureAwareMeshDecimator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let decimationPipeline: MTLComputePipelineState
    private let qualityPipeline: MTLComputePipelineState
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "MeshDecimation")
    private let performanceMonitor = PerformanceMonitor.shared
    
    struct DecimationConfig {
        let targetTriangleCount: Int
        let featurePreservationWeight: Float
        let maxEdgeLength: Float
        let minQualityThreshold: Float
        let adaptiveDecimation: Bool
        
        static let `default` = DecimationConfig(
            targetTriangleCount: 50000,
            featurePreservationWeight: 0.8,
            maxEdgeLength: 0.1,
            minQualityThreshold: 0.7,
            adaptiveDecimation: true
        )
    }
    
    struct DecimationResult {
        let mesh: MeshData
        let metrics: DecimationMetrics
        let preservedFeatures: [AnatomicalFeature]
    }
    
    struct DecimationMetrics {
        let triangleReduction: Float
        let qualityScore: Float
        let featurePreservation: Float
        let maxError: Float
        let processingTime: TimeInterval
        
        var meetsQualityRequirements: Bool {
            qualityScore >= ClinicalConstants.minimumMeshQuality &&
            featurePreservation >= ClinicalConstants.featurePreservationThreshold &&
            maxError <= ClinicalConstants.maximumDecimationError
        }
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw DecimationError.initializationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        // Initialize compute pipelines
        self.decimationPipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "decimateMeshKernel")!
        )
        
        self.qualityPipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "evaluateQualityKernel")!
        )
    }
    
    func decimateMesh(
        _ mesh: MeshData,
        features: [AnatomicalFeature],
        config: DecimationConfig = .default
    ) async throws -> DecimationResult {
        let perfID = performanceMonitor.startMeasuring("meshDecimation")
        defer { performanceMonitor.endMeasuring("meshDecimation", signpostID: perfID) }
        
        let startTime = CACurrentMediaTime()
        
        // Convert mesh to half-edge data structure for efficient operations
        var halfEdgeMesh = try HalfEdgeMesh(mesh)
        
        // Calculate feature importance for each vertex
        let vertexImportance = calculateVertexImportance(
            halfEdgeMesh,
            features: features,
            weight: config.featurePreservationWeight
        )
        
        // Initialize priority queue for edge collapses
        var collapseQueue = PriorityQueue<EdgeCollapse>()
        
        // Populate queue with potential edge collapses
        try populateCollapseQueue(
            &collapseQueue,
            mesh: halfEdgeMesh,
            importance: vertexImportance,
            config: config
        )
        
        // Perform edge collapses until target reached or quality threshold hit
        var currentTriangleCount = mesh.triangles.count
        var preservedFeatures = features
        
        while currentTriangleCount > config.targetTriangleCount,
              let collapse = collapseQueue.dequeue() {
            
            // Skip if edge no longer valid
            if !collapse.isValid(in: halfEdgeMesh) { continue }
            
            // Calculate local error metric
            let error = calculateCollapseError(
                collapse,
                mesh: halfEdgeMesh,
                importance: vertexImportance
            )
            
            // Check if collapse maintains quality
            guard error <= ClinicalConstants.maximumDecimationError else { continue }
            
            // Perform edge collapse
            let affected = try performCollapse(
                collapse,
                mesh: &halfEdgeMesh,
                features: &preservedFeatures
            )
            
            // Update collapse queue for affected region
            try updateCollapseQueue(
                &collapseQueue,
                affected: affected,
                mesh: halfEdgeMesh,
                importance: vertexImportance,
                config: config
            )
            
            currentTriangleCount -= 2
        }
        
        // Convert back to regular mesh representation
        let decimatedMesh = halfEdgeMesh.toMeshData()
        
        // Calculate final metrics
        let metrics = DecimationMetrics(
            triangleReduction: Float(mesh.triangles.count - decimatedMesh.triangles.count) / Float(mesh.triangles.count),
            qualityScore: calculateQualityScore(decimatedMesh),
            featurePreservation: calculateFeaturePreservation(features, preservedFeatures),
            maxError: calculateMaxError(original: mesh, decimated: decimatedMesh),
            processingTime: CACurrentMediaTime() - startTime
        )
        
        // Validate results
        guard metrics.meetsQualityRequirements else {
            throw DecimationError.qualityRequirementsNotMet(metrics)
        }
        
        return DecimationResult(
            mesh: decimatedMesh,
            metrics: metrics,
            preservedFeatures: preservedFeatures
        )
    }
    
    // MARK: - Private Methods
    
    private func calculateVertexImportance(
        _ mesh: HalfEdgeMesh,
        features: [AnatomicalFeature],
        weight: Float
    ) -> [Float] {
        var importance = [Float](repeating: 0, count: mesh.vertices.count)
        
        // Calculate base importance from geometric properties
        for (idx, vertex) in mesh.vertices.enumerated() {
            let curvature = calculateVertexCurvature(vertex, mesh: mesh)
            let valence = calculateVertexValence(vertex, mesh: mesh)
            
            importance[idx] = curvature * Float(valence)
        }
        
        // Add feature-based importance
        for feature in features {
            if let nearestIdx = findNearestVertex(feature.position, in: mesh) {
                let radius = feature.confidence * 0.1 // Influence radius based on confidence
                
                // Apply gaussian falloff of importance around feature
                for (idx, vertex) in mesh.vertices.enumerated() {
                    let distance = length(vertex.position - feature.position)
                    let falloff = exp(-distance * distance / (2 * radius * radius))
                    importance[idx] += weight * feature.confidence * falloff
                }
            }
        }
        
        // Normalize importance values
        let maxImportance = importance.max() ?? 1
        return importance.map { $0 / maxImportance }
    }
    
    private func calculateCollapseError(
        _ collapse: EdgeCollapse,
        mesh: HalfEdgeMesh,
        importance: [Float]
    ) -> Float {
        // Calculate quadric error metric
        let q1 = calculateQuadricMatrix(collapse.v1, mesh: mesh)
        let q2 = calculateQuadricMatrix(collapse.v2, mesh: mesh)
        let q = q1 + q2
        
        // Find optimal position that minimizes error
        let optimalPosition = solveQuadricPosition(q)
        
        // Calculate error at optimal position
        var error = evaluateQuadricError(optimalPosition, matrix: q)
        
        // Weight error by vertex importance
        error *= max(
            importance[collapse.v1.index],
            importance[collapse.v2.index]
        )
        
        return error
    }
    
    private func performCollapse(
        _ collapse: EdgeCollapse,
        mesh: inout HalfEdgeMesh,
        features: inout [AnatomicalFeature]
    ) throws -> Set<Vertex> {
        // Calculate optimal position for collapsed vertex
        let optimalPosition = calculateOptimalPosition(
            collapse.v1,
            collapse.v2,
            mesh: mesh
        )
        
        // Store vertices affected by collapse
        let affected = mesh.getVertexOneRing(collapse.v1)
        affected.formUnion(mesh.getVertexOneRing(collapse.v2))
        
        // Update mesh connectivity
        try mesh.collapseEdge(
            from: collapse.v1,
            to: collapse.v2,
            newPosition: optimalPosition
        )
        
        // Update feature positions if needed
        updateFeaturePositions(
            &features,
            oldPosition1: collapse.v1.position,
            oldPosition2: collapse.v2.position,
            newPosition: optimalPosition
        )
        
        return affected
    }
    
    private func updateCollapseQueue(
        _ queue: inout PriorityQueue<EdgeCollapse>,
        affected: Set<Vertex>,
        mesh: HalfEdgeMesh,
        importance: [Float],
        config: DecimationConfig
    ) throws {
        // Remove invalid collapses
        queue.removeAll { collapse in
            affected.contains(collapse.v1) || affected.contains(collapse.v2)
        }
        
        // Add new potential collapses for affected region
        for vertex in affected {
            for neighbor in mesh.getVertexNeighbors(vertex) {
                let collapse = EdgeCollapse(v1: vertex, v2: neighbor)
                let error = calculateCollapseError(
                    collapse,
                    mesh: mesh,
                    importance: importance
                )
                
                if error <= config.minQualityThreshold {
                    queue.enqueue(collapse, priority: -error)
                }
            }
        }
    }
    
    private func calculateQualityScore(_ mesh: MeshData) -> Float {
        var score: Float = 0
        // Implementation details...
        return score
    }
    
    private func calculateFeaturePreservation(
        _ original: [AnatomicalFeature],
        _ preserved: [AnatomicalFeature]
    ) -> Float {
        var totalPreservation: Float = 0
        
        for originalFeature in original {
            if let preservedFeature = preserved.first(where: { $0.uniqueID == originalFeature.uniqueID }) {
                let positionDiff = length(preservedFeature.position - originalFeature.position)
                let normalDiff = 1 - abs(dot(preservedFeature.normal, originalFeature.normal))
                
                totalPreservation += (1 - positionDiff) * (1 - normalDiff)
            }
        }
        
        return totalPreservation / Float(original.count)
    }
}

// MARK: - Supporting Types

private struct EdgeCollapse {
    let v1: Vertex
    let v2: Vertex
    let error: Float
    
    func isValid(in mesh: HalfEdgeMesh) -> Bool {
        mesh.vertices.contains(v1) &&
        mesh.vertices.contains(v2) &&
        mesh.areConnected(v1, v2)
    }
}

private struct HalfEdge {
    let vertex: Vertex
    let face: Triangle
    var next: HalfEdge?
    var pair: HalfEdge?
}

private struct Vertex {
    let index: Int
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var edges: Set<HalfEdge>
}

private struct Triangle {
    let vertices: (Vertex, Vertex, Vertex)
    var normal: SIMD3<Float>
}

enum DecimationError: Error {
    case initializationFailed
    case invalidMeshTopology
    case qualityRequirementsNotMet(DecimationMetrics)
}

// Priority queue implementation
private struct PriorityQueue<T> {
    private var heap: [(T, Float)] = []
    
    mutating func enqueue(_ element: T, priority: Float) {
        heap.append((element, priority))
        siftUp(from: heap.count - 1)
    }
    
    mutating func dequeue() -> T? {
        guard !heap.isEmpty else { return nil }
        
        let result = heap[0].0
        heap[0] = heap[heap.count - 1]
        heap.removeLast()
        
        if !heap.isEmpty {
            siftDown(from: 0)
        }
        
        return result
    }
    
    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = (child - 1) / 2
        
        while child > 0 && heap[child].1 < heap[parent].1 {
            heap.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }
    
    private mutating func siftDown(from index: Int) {
        var parent = index
        
        while true {
            let leftChild = 2 * parent + 1
            let rightChild = leftChild + 1
            var candidate = parent
            
            if leftChild < heap.count && heap[leftChild].1 < heap[candidate].1 {
                candidate = leftChild
            }
            
            if rightChild < heap.count && heap[rightChild].1 < heap[candidate].1 {
                candidate = rightChild
            }
            
            if candidate == parent {
                return
            }
            
            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }
    
    mutating func removeAll(where shouldBeRemoved: (T) -> Bool) {
        heap.removeAll { shouldBeRemoved($0.0) }
        buildHeap()
    }
    
    private mutating func buildHeap() {
        for i in stride(from: heap.count/2 - 1, through: 0, by: -1) {
            siftDown(from: i)
        }
    }
}