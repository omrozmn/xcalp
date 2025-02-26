import Foundation
import Metal
import QuartzCore

class MeshPerformanceMonitor {
    static let shared = MeshPerformanceMonitor()
    
    struct PerformanceMetrics {
        let processingTime: TimeInterval
        let memoryUsage: Int64
        let featurePreservationScore: Float
        let topologyQualityScore: Float
        let originalVertexCount: Int
        let optimizedVertexCount: Int
    }
    
    private var metrics: [String: PerformanceMetrics] = [:]
    private let queue = DispatchQueue(label: "com.xcalp.meshPerformance")
    
    func startTracking(_ meshId: String, originalVertexCount: Int) {
        queue.async {
            self.metrics[meshId] = PerformanceMetrics(
                processingTime: 0,
                memoryUsage: 0,
                featurePreservationScore: 0,
                topologyQualityScore: 0,
                originalVertexCount: originalVertexCount,
                optimizedVertexCount: originalVertexCount
            )
        }
    }
    
    func updateMetrics(_ meshId: String, metrics: PerformanceMetrics) {
        queue.async {
            self.metrics[meshId] = metrics
        }
    }
    
    func generateReport(_ meshId: String) -> PerformanceReport {
        let metrics = self.metrics[meshId]
        
        return PerformanceReport(
            processingTimeReduction: calculateTimeReduction(metrics?.processingTime ?? 0),
            memoryOptimization: calculateMemoryOptimization(metrics?.memoryUsage ?? 0),
            featurePreservation: metrics?.featurePreservationScore ?? 0,
            qualityImprovement: calculateQualityImprovement(metrics?.topologyQualityScore ?? 0),
            vertexReduction: calculateVertexReduction(
                original: metrics?.originalVertexCount ?? 0,
                optimized: metrics?.optimizedVertexCount ?? 0
            )
        )
    }
}