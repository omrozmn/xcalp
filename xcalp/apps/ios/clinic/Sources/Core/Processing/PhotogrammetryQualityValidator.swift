import Foundation
import CoreImage
import Vision
import os.log

final class PhotogrammetryQualityValidator {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "PhotogrammetryQualityValidator")
    private let qualityThresholds = PhotogrammetryQualityThresholds()
    
    struct PhotogrammetryQualityMetrics {
        let sharpness: Float
        let brightness: Float
        let contrast: Float
        let coverage: Float
        let featureCount: Int
        
        var isAcceptable: Bool {
            sharpness >= PhotogrammetryQualityThresholds.minSharpness &&
            brightness >= PhotogrammetryQualityThresholds.minBrightness &&
            brightness <= PhotogrammetryQualityThresholds.maxBrightness &&
            contrast >= PhotogrammetryQualityThresholds.minContrast &&
            coverage >= PhotogrammetryQualityThresholds.minCoverage &&
            featureCount >= PhotogrammetryQualityThresholds.minFeatureCount
        }
    }
    
    func validateImage(_ ciImage: CIImage) async throws -> PhotogrammetryQualityMetrics {
        async let sharpness = calculateSharpness(ciImage)
        async let brightness = calculateBrightness(ciImage)
        async let contrast = calculateContrast(ciImage)
        async let coverage = calculateCoverage(ciImage)
        async let featureCount = detectFeatures(ciImage)
        
        return try await PhotogrammetryQualityMetrics(
            sharpness: sharpness,
            brightness: brightness,
            contrast: contrast,
            coverage: coverage,
            featureCount: featureCount
        )
    }
    
    private func calculateSharpness(_ image: CIImage) async throws -> Float {
        let laplacian = image
            .applyingFilter("CILaplacian")
            .applyingFilter("CIAverageFilter")
        
        let outputImage = try await laplacian.averageValue()
        return Float(outputImage.x + outputImage.y + outputImage.z) / 3.0
    }
    
    private func calculateBrightness(_ image: CIImage) async throws -> Float {
        let outputImage = try await image
            .applyingFilter("CIAverageFilter")
            .averageValue()
        
        return Float(outputImage.x + outputImage.y + outputImage.z) / 3.0
    }
    
    private func calculateContrast(_ image: CIImage) async throws -> Float {
        let histogram = try await image.histogram()
        let mean = histogram.mean
        let variance = histogram.variance
        
        return Float(sqrt(variance) / mean)
    }
    
    private func calculateCoverage(_ image: CIImage) async throws -> Float {
        let threshold = image.applyingFilter("CIColorThreshold",
                                           parameters: ["inputThreshold": 0.1])
        
        let totalPixels = image.extent.width * image.extent.height
        let coveragePixels = try await threshold
            .applyingFilter("CIAreaAverage",
                          parameters: ["inputExtent": image.extent])
            .averageValue()
        
        return Float(coveragePixels.x * totalPixels)
    }
    
    private func detectFeatures(_ image: CIImage) async throws -> Int {
        let request = VNDetectFeaturePrintsRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            return 0
        }
        
        return observations.count
    }
}

struct PhotogrammetryQualityThresholds {
    static let minSharpness: Float = 0.4
    static let minBrightness: Float = 0.3
    static let maxBrightness: Float = 0.8
    static let minContrast: Float = 0.5
    static let minCoverage: Float = 0.85
    static let minFeatureCount: Int = 100
}