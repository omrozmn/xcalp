import Foundation

extension AnalyticsService {
    func logScanMetrics(
        originalVertexCount: Int,
        optimizedVertexCount: Int,
        processingTime: TimeInterval,
        quality: MeshProcessor.MeshQuality
    ) {
        logEvent(
            "scan_processed",
            parameters: [
                "original_vertex_count": originalVertexCount,
                "optimized_vertex_count": optimizedVertexCount,
                "processing_time": processingTime,
                "vertex_density": quality.vertexDensity,
                "surface_smoothness": quality.surfaceSmoothness,
                "normal_consistency": quality.normalConsistency,
                "hole_count": quality.holes.count
            ]
        )
    }
    
    func logScanQuality(
        quality: ScanningFeature.ScanQuality,
        meshDensity: Float,
        duration: TimeInterval
    ) {
        logEvent(
            "scan_quality",
            parameters: [
                "quality": quality.rawValue,
                "mesh_density": meshDensity,
                "duration": duration
            ]
        )
    }
}
