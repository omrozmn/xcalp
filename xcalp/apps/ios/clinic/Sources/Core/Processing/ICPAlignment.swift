import Foundation
import simd

class ICPAlignment {
    private let maxIterations: Int
    private let convergenceThreshold: Float
    
    init(maxIterations: Int = 50, convergenceThreshold: Float = 0.001) {
        self.maxIterations = maxIterations
        self.convergenceThreshold = convergenceThreshold
    }
    
    func align(source: [SIMD3<Float>], target: [SIMD3<Float>]) -> (transform: simd_float4x4, error: Float) {
        var currentSource = source
        var transform = matrix_identity_float4x4
        var prevError: Float = Float.infinity
        
        for _ in 0..<maxIterations {
            // Find corresponding points
            let correspondences = findCorrespondences(source: currentSource, target: target)
            
            // Calculate centroids
            let sourceCentroid = calculateCentroid(currentSource)
            let targetCentroid = calculateCentroid(correspondences)
            
            // Calculate optimal rotation and translation
            let (rotation, translation) = calculateTransform(
                source: currentSource,
                target: correspondences,
                sourceCentroid: sourceCentroid,
                targetCentroid: targetCentroid
            )
            
            // Update transform
            let iterationTransform = createTransformMatrix(rotation: rotation, translation: translation)
            transform = matrix_multiply(iterationTransform, transform)
            
            // Apply transform to source points
            currentSource = currentSource.map { transformPoint($0, transform: iterationTransform) }
            
            // Calculate error
            let error = calculateError(source: currentSource, target: correspondences)
            
            // Check convergence
            if abs(prevError - error) < convergenceThreshold {
                break
            }
            prevError = error
        }
        
        return (transform, prevError)
    }
    
    private func findCorrespondences(source: [SIMD3<Float>], target: [SIMD3<Float>]) -> [SIMD3<Float>] {
        source.map { sourcePoint in
            target.min { a, b in
                distance(sourcePoint, a) < distance(sourcePoint, b)
            } ?? sourcePoint
        }
    }
    
    private func calculateCentroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        let sum = points.reduce(SIMD3<Float>.zero, +)
        return sum / Float(points.count)
    }
    
    private func calculateTransform(
        source: [SIMD3<Float>],
        target: [SIMD3<Float>],
        sourceCentroid: SIMD3<Float>,
        targetCentroid: SIMD3<Float>
    ) -> (rotation: simd_float3x3, translation: SIMD3<Float>) {
        // Calculate covariance matrix
        var covariance = matrix_identity_float3x3
        for i in 0..<source.count {
            let sourceOffset = source[i] - sourceCentroid
            let targetOffset = target[i] - targetCentroid
            covariance += matrix_multiply(
                simd_float3x3(columns: (sourceOffset, SIMD3<Float>.zero, SIMD3<Float>.zero)),
                simd_float3x3(columns: (targetOffset, SIMD3<Float>.zero, SIMD3<Float>.zero))
            )
        }
        
        // SVD decomposition
        let (U, _, V) = svd3x3(covariance)
        
        // Calculate optimal rotation
        let rotation = matrix_multiply(V, U.transpose)
        
        // Calculate optimal translation
        let translation = targetCentroid - matrix_multiply(rotation, sourceCentroid)
        
        return (rotation, translation)
    }
    
    private func createTransformMatrix(rotation: simd_float3x3, translation: SIMD3<Float>) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(rotation.columns.0, 0)
        transform.columns.1 = SIMD4<Float>(rotation.columns.1, 0)
        transform.columns.2 = SIMD4<Float>(rotation.columns.2, 0)
        transform.columns.3 = SIMD4<Float>(translation, 1)
        return transform
    }
    
    private func transformPoint(_ point: SIMD3<Float>, transform: simd_float4x4) -> SIMD3<Float> {
        let homogeneous = SIMD4<Float>(point.x, point.y, point.z, 1)
        let transformed = matrix_multiply(transform, homogeneous)
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }
    
    private func calculateError(source: [SIMD3<Float>], target: [SIMD3<Float>]) -> Float {
        var totalError: Float = 0
        for i in 0..<source.count {
            totalError += distance(source[i], target[i])
        }
        return totalError / Float(source.count)
    }
    
    private func svd3x3(_ matrix: simd_float3x3) -> (U: simd_float3x3, S: SIMD3<Float>, V: simd_float3x3) {
        // Simplified SVD implementation for 3x3 matrices
        // In practice, you would use a numerical library like Accelerate
        // This is a placeholder that returns identity matrices
        (matrix_identity_float3x3, SIMD3<Float>(1, 1, 1), matrix_identity_float3x3)
    }
}

private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    length(a - b)
}
