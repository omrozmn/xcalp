import Foundation
import Metal
import simd
@testable import xcalp

final class TestDataManager {
    private let device: MTLDevice
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let meshCache: NSCache<NSString, CachedMeshData>
    private var activeTestData: [UUID: TestDataContext] = [:]
    
    struct TestDataContext {
        let id: UUID
        let creationTime: Date
        let meshData: [MeshData]
        let temporaryFiles: [URL]
        let cleanupTasks: [() -> Void]
    }
    
    class CachedMeshData {
        let mesh: MeshData
        let metadata: CacheMetadata
        
        struct CacheMetadata {
            let creationTime: Date
            let lastAccessed: Date
            let accessCount: Int
            let memorySize: Int
        }
        
        init(mesh: MeshData, metadata: CacheMetadata) {
            self.mesh = mesh
            self.metadata = metadata
        }
    }
    
    enum MeshDataType {
        case simple
        case complex
        case corrupted
        case benchmark
        
        var vertexCount: Int {
            switch self {
            case .simple: return 1000
            case .complex: return 10000
            case .corrupted: return 5000
            case .benchmark: return 100000
            }
        }
    }
    
    init(device: MTLDevice) throws {
        self.device = device
        self.fileManager = FileManager.default
        
        // Set up temporary directory
        let tempPath = NSTemporaryDirectory()
        self.temporaryDirectory = URL(fileURLWithPath: tempPath)
            .appendingPathComponent("TestData")
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        
        // Initialize mesh cache
        self.meshCache = NSCache<NSString, CachedMeshData>()
        meshCache.countLimit = 100
        meshCache.totalCostLimit = 512 * 1024 * 1024 // 512MB
        
        // Start cleanup timer
        startCleanupTimer()
    }
    
    func generateTestData(
        type: MeshDataType,
        count: Int = 1,
        variations: [MeshVariation] = []
    ) throws -> [MeshData] {
        var meshes: [MeshData] = []
        
        for _ in 0..<count {
            var mesh = try generateBaseMesh(type: type)
            
            // Apply variations
            for variation in variations {
                mesh = try applyVariation(variation, to: mesh)
            }
            
            meshes.append(mesh)
        }
        
        return meshes
    }
    
    func beginTestContext() -> UUID {
        let contextId = UUID()
        activeTestData[contextId] = TestDataContext(
            id: contextId,
            creationTime: Date(),
            meshData: [],
            temporaryFiles: [],
            cleanupTasks: []
        )
        return contextId
    }
    
    func registerTestData(
        _ data: MeshData,
        forContext contextId: UUID
    ) throws {
        guard var context = activeTestData[contextId] else {
            throw TestDataError.invalidContext
        }
        
        // Store mesh data
        context.meshData.append(data)
        activeTestData[contextId] = context
        
        // Cache for reuse
        cacheMeshData(data)
    }
    
    func createTemporaryFile(
        forContext contextId: UUID,
        prefix: String = "test",
        extension: String = "mesh"
    ) throws -> URL {
        guard var context = activeTestData[contextId] else {
            throw TestDataError.invalidContext
        }
        
        let fileName = "\(prefix)_\(UUID().uuidString).\(`extension`)"
        let fileURL = temporaryDirectory.appendingPathComponent(fileName)
        
        context.temporaryFiles.append(fileURL)
        activeTestData[contextId] = context
        
        return fileURL
    }
    
    func cleanup(contextId: UUID) throws {
        guard let context = activeTestData[contextId] else {
            throw TestDataError.invalidContext
        }
        
        // Execute cleanup tasks
        for task in context.cleanupTasks {
            task()
        }
        
        // Remove temporary files
        for fileURL in context.temporaryFiles {
            try? fileManager.removeItem(at: fileURL)
        }
        
        // Clear context
        activeTestData.removeValue(forKey: contextId)
    }
    
    // MARK: - Private Methods
    
    private func generateBaseMesh(type: MeshDataType) throws -> MeshData {
        // Check cache first
        let cacheKey = "\(type)_base" as NSString
        if let cached = meshCache.object(forKey: cacheKey) {
            return cached.mesh
        }
        
        // Generate new mesh
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        switch type {
        case .simple:
            return try generateSimpleMesh(vertexCount: type.vertexCount)
        case .complex:
            return try generateComplexMesh(vertexCount: type.vertexCount)
        case .corrupted:
            return try generateCorruptedMesh(vertexCount: type.vertexCount)
        case .benchmark:
            return try generateBenchmarkMesh(vertexCount: type.vertexCount)
        }
    }
    
    private func generateSimpleMesh(vertexCount: Int) throws -> MeshData {
        // Generate a simple sphere
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var confidence: [Float] = []
        
        let radius: Float = 1.0
        let rows = Int(sqrt(Float(vertexCount)))
        let cols = rows
        
        for i in 0...rows {
            let phi = Float.pi * Float(i) / Float(rows)
            for j in 0...cols {
                let theta = 2 * Float.pi * Float(j) / Float(cols)
                
                let x = radius * sin(phi) * cos(theta)
                let y = radius * sin(phi) * sin(theta)
                let z = radius * cos(phi)
                
                let vertex = SIMD3<Float>(x, y, z)
                vertices.append(vertex)
                normals.append(normalize(vertex))
                confidence.append(1.0)
                
                if i < rows && j < cols {
                    let current = UInt32(i * (cols + 1) + j)
                    let next = current + 1
                    let bottom = current + UInt32(cols + 1)
                    let bottomNext = bottom + 1
                    
                    indices.append(contentsOf: [current, next, bottom])
                    indices.append(contentsOf: [next, bottomNext, bottom])
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
    
    private func generateComplexMesh(vertexCount: Int) throws -> MeshData {
        // Generate a more complex shape with features
        var base = try generateSimpleMesh(vertexCount: vertexCount)
        
        // Add noise and features
        for i in 0..<base.vertices.count {
            let noise = SIMD3<Float>(
                Float.random(in: -0.1...0.1),
                Float.random(in: -0.1...0.1),
                Float.random(in: -0.1...0.1)
            )
            base.vertices[i] += noise
            base.normals[i] = normalize(base.normals[i] + noise * 0.2)
            base.confidence[i] = Float.random(in: 0.8...1.0)
        }
        
        return base
    }
    
    private func generateCorruptedMesh(vertexCount: Int) throws -> MeshData {
        var base = try generateSimpleMesh(vertexCount: vertexCount)
        
        // Introduce corruptions
        for i in stride(from: 0, to: base.vertices.count, by: 10) {
            base.vertices[i] = .zero // Create degenerate vertices
            base.normals[i] = .zero // Invalid normals
            base.confidence[i] = -1.0 // Invalid confidence
        }
        
        // Add invalid indices
        for i in stride(from: 0, to: base.indices.count, by: 100) {
            base.indices[i] = UInt32(vertexCount + 1) // Out of bounds
        }
        
        return base
    }
    
    private func generateBenchmarkMesh(vertexCount: Int) throws -> MeshData {
        // Generate a high-detail mesh for benchmarking
        var base = try generateSimpleMesh(vertexCount: vertexCount)
        
        // Add complexity for benchmark testing
        for i in 0..<base.vertices.count {
            let phase = Float(i) / Float(base.vertices.count) * 2 * .pi
            let displacement = sin(phase * 10) * 0.1
            base.vertices[i] *= (1.0 + displacement)
            base.normals[i] = normalize(base.normals[i])
            base.confidence[i] = abs(sin(phase * 5))
        }
        
        return base
    }
    
    private func applyVariation(_ variation: MeshVariation, to mesh: MeshData) throws -> MeshData {
        var result = mesh
        
        switch variation {
        case .noise(let amplitude):
            // Add random noise to vertices
            for i in 0..<result.vertices.count {
                let noise = SIMD3<Float>(
                    Float.random(in: -amplitude...amplitude),
                    Float.random(in: -amplitude...amplitude),
                    Float.random(in: -amplitude...amplitude)
                )
                result.vertices[i] += noise
            }
            
        case .scale(let factor):
            // Scale the mesh
            for i in 0..<result.vertices.count {
                result.vertices[i] *= factor
            }
            
        case .rotation(let angle, let axis):
            // Rotate the mesh
            let rotation = simd_quatf(angle: angle, axis: normalize(axis))
            for i in 0..<result.vertices.count {
                result.vertices[i] = rotation.act(result.vertices[i])
                result.normals[i] = rotation.act(result.normals[i])
            }
            
        case .confidence(let range):
            // Modify confidence values
            for i in 0..<result.confidence.count {
                result.confidence[i] = Float.random(in: range)
            }
        }
        
        return result
    }
    
    private func cacheMeshData(_ mesh: MeshData) {
        let key = "\(mesh.metadata.source)_\(mesh.vertices.count)" as NSString
        let metadata = CachedMeshData.CacheMetadata(
            creationTime: Date(),
            lastAccessed: Date(),
            accessCount: 1,
            memorySize: MemoryLayout<SIMD3<Float>>.size * mesh.vertices.count
        )
        let cachedData = CachedMeshData(mesh: mesh, metadata: metadata)
        meshCache.setObject(cachedData, forKey: key)
    }
    
    private func startCleanupTimer() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.performCleanup()
        }
    }
    
    private func performCleanup() {
        // Clean up old temporary files
        let oldFiles = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        
        let expirationInterval: TimeInterval = 3600 // 1 hour
        let now = Date()
        
        oldFiles?.forEach { url in
            guard let creation = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  now.timeIntervalSince(creation) > expirationInterval else {
                return
            }
            try? fileManager.removeItem(at: url)
        }
        
        // Clean up old test contexts
        let expiredContexts = activeTestData.filter {
            now.timeIntervalSince($0.value.creationTime) > expirationInterval
        }
        
        expiredContexts.forEach { contextId, _ in
            try? cleanup(contextId: contextId)
        }
    }
}

enum TestDataError: Error {
    case invalidContext
    case generationFailed
    case invalidData
}

enum MeshVariation {
    case noise(amplitude: Float)
    case scale(factor: Float)
    case rotation(angle: Float, axis: SIMD3<Float>)
    case confidence(range: ClosedRange<Float>)
}