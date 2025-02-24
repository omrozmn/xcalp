import Foundation

private struct QualityMetrics {
    var pointDensity: Float = 0
    var depthConsistency: Float = 0
    var normalConsistency: Float = 0
    var featureMatchQuality: Float = 0
    var imageQuality: Float = 0
    var coverageCompleteness: Float = 0
}

private struct FusionMetrics {
    var dataOverlap: Float = 0
    var geometricConsistency: Float = 0
    var scaleConsistency: Float = 0
}

struct FusionConfiguration {
    let lidarWeight: Float
    let photoWeight: Float
}
