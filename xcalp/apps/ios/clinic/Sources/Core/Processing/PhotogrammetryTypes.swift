import Foundation
import simd

/// Protocol defining photogrammetry scan data
public protocol PhotogrammetryData {
    /// Features detected in the photogrammetry data
    var features: [Feature] { get }
    /// Camera parameters used during capture
    var cameraParameters: CameraParameters { get }
}

/// Protocol defining a detected feature in photogrammetry data
public protocol Feature {
    /// 3D position of the feature
    var position: SIMD3<Float> { get }
    /// Confidence score of the feature detection (0-1)
    var confidence: Float { get }
}

/// Camera parameters used during photogrammetry capture
public struct CameraParameters {
    /// Focal length in millimeters
    public var focalLength: Float = 0
    /// Principal point offset
    public var principalPoint: SIMD2<Float> = .zero
    /// Image dimensions in pixels
    public var imageSize: SIMD2<Float> = .zero
    /// Distortion coefficients
    public var distortion: SIMD4<Float> = .zero
    
    /// Creates a new CameraParameters instance
    /// - Parameters:
    ///   - focalLength: The focal length in millimeters
    ///   - principalPoint: The principal point offset
    ///   - imageSize: The image dimensions in pixels
    ///   - distortion: The distortion coefficients
    public init(
        focalLength: Float = 0,
        principalPoint: SIMD2<Float> = .zero,
        imageSize: SIMD2<Float> = .zero,
        distortion: SIMD4<Float> = .zero
    ) {
        self.focalLength = focalLength
        self.principalPoint = principalPoint
        self.imageSize = imageSize
        self.distortion = distortion
    }
}
