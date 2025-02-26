import Foundation
import Metal

struct TestConfiguration {
    // Performance thresholds
    static let maxProcessingTime: Float = 5.0 // seconds
    static let maxMemoryUsage: Int = 512 * 1024 * 1024 // 512 MB
    static let minFPS: Float = 30.0
    
    // Quality thresholds
    static let minimumPointDensity: Float = 100.0 // points per cubic meter
    static let minimumSurfaceCompleteness: Float = 0.95
    static let maximumNoiseLevel: Float = 0.01 // meters
    static let minimumFeaturePreservation: Float = 0.8
    
    // Concurrency settings
    static let maxConcurrentOperations: Int = 4
    static let operationTimeout: TimeInterval = 30.0
    
    // Test mesh parameters
    static let testMeshResolutions = [32, 64, 128, 256]
    static let testMeshTypes: [TestMeshGenerator.MeshType] = [.sphere, .cube, .cylinder]
    
    // Error injection settings
    static let errorInjectionProbability: Float = 0.2
    static let errorSeverityLevels: [Float] = [0.1, 0.3, 0.5]
    
    // Memory pressure test levels
    static let memoryPressureLevels: [Float] = [0.5, 0.75, 0.9]
    
    // Device capabilities
    static let requiredMetalFeatures: MTLFeatureSet = .iOS_GPUFamily3_v4
    
    static func validateDeviceCapabilities(_ device: MTLDevice) throws {
        guard device.supportsFeatureSet(requiredMetalFeatures) else {
            throw ConfigurationError.insufficientGPUCapabilities
        }
    }
    
    static func getTestParameters(for environment: TestEnvironment) -> TestParameters {
        switch environment {
        case .development:
            return TestParameters(
                iterations: 5,
                meshResolution: 64,
                timeoutMultiplier: 2.0,
                memoryMultiplier: 1.5
            )
        case .staging:
            return TestParameters(
                iterations: 10,
                meshResolution: 128,
                timeoutMultiplier: 1.5,
                memoryMultiplier: 1.2
            )
        case .production:
            return TestParameters(
                iterations: 20,
                meshResolution: 256,
                timeoutMultiplier: 1.0,
                memoryMultiplier: 1.0
            )
        }
    }
}

struct TestParameters {
    let iterations: Int
    let meshResolution: Int
    let timeoutMultiplier: Double
    let memoryMultiplier: Double
    
    var adjustedTimeout: TimeInterval {
        return TestConfiguration.operationTimeout * timeoutMultiplier
    }
    
    var adjustedMemoryLimit: Int {
        return Int(Double(TestConfiguration.maxMemoryUsage) * memoryMultiplier)
    }
}

enum TestEnvironment {
    case development
    case staging
    case production
}

enum ConfigurationError: Error {
    case insufficientGPUCapabilities
    case invalidConfiguration
    case unsupportedEnvironment
    
    var localizedDescription: String {
        switch self {
        case .insufficientGPUCapabilities:
            return "Device does not support required Metal feature set"
        case .invalidConfiguration:
            return "Invalid test configuration parameters"
        case .unsupportedEnvironment:
            return "Unsupported test environment"
        }
    }
}