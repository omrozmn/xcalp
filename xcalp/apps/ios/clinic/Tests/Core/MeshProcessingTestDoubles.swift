import Metal
import simd
@testable import xcalp

// MARK: - Mock Metal Device

class MockMetalDevice: MTLDevice {
    var maxBufferLength: Int = 1024 * 1024 * 1024 // 1GB
    var name: String = "Mock Metal Device"
    var registryID: UInt64 = 1
    var isHeadless: Bool = false
    var isLowPower: Bool = false
    var isRemovable: Bool = false
    var hasUnifiedMemory: Bool = true
    var recommendedMaxWorkingSetSize: UInt64 = UInt64(4 * 1024 * 1024 * 1024) // 4GB
    var location: MTLDeviceLocation = .builtIn
    var locationNumber: UInt32 = 0
    var maxTransferRate: UInt64 = 0
    var depth24Stencil8PixelFormatSupported: Bool = true
    var readWriteTextureSupport: MTLReadWriteTextureTier = .tier2
    var argumentBuffersSupport: MTLArgumentBuffersTier = .tier2
    var areRasterOrderGroupsSupported: Bool = true
    var supportsPullModelInterpolation: Bool = true
    var areBarycentricCoordsSupported: Bool = true
    var supportsShaderBarycentricCoordinates: Bool = true
    var currentAllocatedSize: UInt64 = 0
    
    var shouldFailBufferCreation: Bool = false
    var shouldFailCommandQueueCreation: Bool = false
    
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        guard !shouldFailBufferCreation else { return nil }
        return MockBuffer(device: self, length: length)
    }
    
    func makeCommandQueue() -> MTLCommandQueue? {
        guard !shouldFailCommandQueueCreation else { return nil }
        return MockCommandQueue()
    }
    
    // Implement other required MTLDevice methods...
}

// MARK: - Mock Buffer

class MockBuffer: MTLBuffer {
    let device: MTLDevice
    let length: Int
    var contents: UnsafeMutableRawPointer
    let allocatedSize: Int
    
    init(device: MTLDevice, length: Int) {
        self.device = device
        self.length = length
        self.allocatedSize = length
        self.contents = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
    }
    
    deinit {
        contents.deallocate()
    }
}

// MARK: - Mock Command Queue

class MockCommandQueue: MTLCommandQueue {
    var label: String?
    var device: MTLDevice = MockMetalDevice()
    
    func makeCommandBuffer() -> MTLCommandBuffer? {
        return MockCommandBuffer()
    }
}

// MARK: - Mock Command Buffer

class MockCommandBuffer: MTLCommandBuffer {
    var device: MTLDevice = MockMetalDevice()
    var commandQueue: MTLCommandQueue?
    var retainedReferences: [Any] = []
    var label: String?
    var kernelStartTime: UInt64 = 0
    var kernelEndTime: UInt64 = 0
    
    func commit() {
        // Simulate command buffer commit
    }
    
    func waitUntilCompleted() {
        // Simulate completion delay
        Thread.sleep(forTimeInterval: 0.01)
    }
}

// MARK: - Mock Mesh Processor

class MockMeshProcessor: MeshProcessing {
    var processingDelay: TimeInterval = 0.1
    var shouldFail: Bool = false
    var processingError: Error?
    var processedMeshes: [MeshData] = []
    
    func process(_ mesh: MeshData) async throws -> MeshData {
        guard !shouldFail else {
            throw processingError ?? ProcessingError.generalError
        }
        
        // Simulate processing delay
        try await Task.sleep(nanoseconds: UInt64(processingDelay * 1_000_000_000))
        
        // Record processed mesh
        processedMeshes.append(mesh)
        
        // Return modified mesh
        return MeshData(
            vertices: mesh.vertices.map { $0 * 0.99 }, // Slight modification
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence.map { min($0 * 1.1, 1.0) },
            metadata: mesh.metadata
        )
    }
}

// MARK: - Mock Quality Analyzer

class MockQualityAnalyzer: QualityAnalyzing {
    var qualityScore: Float = 0.8
    var shouldFail: Bool = false
    var analysisDelay: TimeInterval = 0.05
    var analyzedMeshes: [MeshData] = []
    
    func analyzeMesh(_ mesh: MeshData) async throws -> QualityMetrics {
        guard !shouldFail else {
            throw AnalysisError.qualityCheckFailed
        }
        
        // Simulate analysis delay
        try await Task.sleep(nanoseconds: UInt64(analysisDelay * 1_000_000_000))
        
        // Record analyzed mesh
        analyzedMeshes.append(mesh)
        
        return QualityMetrics(
            pointDensity: Float(mesh.vertices.count) / 1000.0,
            surfaceCompleteness: qualityScore,
            noiseLevel: 1.0 - qualityScore,
            featurePreservation: qualityScore
        )
    }
}

// MARK: - Mock Progress Monitor

class MockProgressMonitor: ProgressMonitoring {
    var recordedProgress: [(ProcessingStage, Double)] = []
    var shouldNotifyFailure: Bool = false
    
    func updateProgress(_ stage: ProcessingStage, progress: Double) {
        recordedProgress.append((stage, progress))
        
        if shouldNotifyFailure && progress > 0.5 {
            NotificationCenter.default.post(
                name: .processingWarning,
                object: nil,
                userInfo: ["message": "Simulated warning"]
            )
        }
    }
    
    func reset() {
        recordedProgress.removeAll()
    }
}

// MARK: - Test Data Generator

class TestMeshGenerator {
    static func generatePlaneMesh(resolution: Int = 10) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        for i in 0...resolution {
            for j in 0...resolution {
                let x = Float(i) / Float(resolution) * 2 - 1
                let z = Float(j) / Float(resolution) * 2 - 1
                
                vertices.append(SIMD3<Float>(x, 0, z))
                normals.append(SIMD3<Float>(0, 1, 0))
                confidence.append(1.0)
                
                if i < resolution && j < resolution {
                    let current = UInt32(i * (resolution + 1) + j)
                    indices.append(current)
                    indices.append(current + 1)
                    indices.append(current + UInt32(resolution + 1))
                    
                    indices.append(current + 1)
                    indices.append(current + UInt32(resolution + 2))
                    indices.append(current + UInt32(resolution + 1))
                }
            }
        }
        
        return MeshData(
            vertices: vertices,
            indices: indices,
            normals: normals,
            confidence: confidence,
            metadata: MeshMetadata(source: .test)
        )
    }
    
    static func generateNoisyMesh(_ baseMesh: MeshData, noiseLevel: Float = 0.1) -> MeshData {
        let noisyVertices = baseMesh.vertices.map { vertex in
            vertex + SIMD3<Float>(
                Float.random(in: -noiseLevel...noiseLevel),
                Float.random(in: -noiseLevel...noiseLevel),
                Float.random(in: -noiseLevel...noiseLevel)
            )
        }
        
        return MeshData(
            vertices: noisyVertices,
            indices: baseMesh.indices,
            normals: baseMesh.normals,
            confidence: baseMesh.confidence,
            metadata: baseMesh.metadata
        )
    }
}

// MARK: - Error Types

enum ProcessingError: Error {
    case generalError
}

enum AnalysisError: Error {
    case qualityCheckFailed
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let processingWarning = Notification.Name("processingWarning")
}