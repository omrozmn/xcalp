import Foundation
import Metal
import simd

final class ErrorInjector {
    enum ErrorType {
        case memoryPressure
        case corruptedVertices
        case invalidIndices
        case misalignedBuffers
        case inconsistentNormals
        case deviceLost
        case timeoutSimulation
    }
    
    struct InjectionConfig {
        let errorType: ErrorType
        let probability: Float
        let severity: Float
        let metadata: [String: Any]
        
        static let standard = InjectionConfig(
            errorType: .corruptedVertices,
            probability: 0.5,
            severity: 0.3,
            metadata: [:]
        )
    }
    
    func injectError(into mesh: MeshData, config: InjectionConfig) -> MeshData {
        guard Float.random(in: 0...1) < config.probability else {
            return mesh
        }
        
        var modifiedMesh = mesh
        
        switch config.config.errorType {
        case .corruptedVertices:
            modifiedMesh = injectVertexCorruption(mesh, severity: config.severity)
        case .invalidIndices:
            modifiedMesh = injectIndexCorruption(mesh, severity: config.severity)
        case .inconsistentNormals:
            modifiedMesh = injectNormalInconsistency(mesh, severity: config.severity)
        default:
            break // Other error types handled separately
        }
        
        return modifiedMesh
    }
    
    func simulateDeviceError(_ device: MTLDevice) throws {
        // Simulate Metal device errors
        throw ErrorInjectionError.simulatedDeviceError
    }
    
    func simulateTimeout<T>(_ operation: () async throws -> T) async throws -> T {
        // Random delay before timeout
        if Bool.random() {
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...3_000_000_000))
            throw ErrorInjectionError.simulatedTimeout
        }
        return try await operation()
    }
    
    private func injectVertexCorruption(_ mesh: MeshData, severity: Float) -> MeshData {
        var vertices = mesh.vertices
        let corruptCount = Int(Float(vertices.count) * severity)
        
        for _ in 0..<corruptCount {
            let index = Int.random(in: 0..<vertices.count)
            vertices[index] = SIMD3<Float>(
                .random(in: -1000...1000),
                .random(in: -1000...1000),
                .random(in: -1000...1000)
            )
        }
        
        return MeshData(
            vertices: vertices,
            indices: mesh.indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
    
    private func injectIndexCorruption(_ mesh: MeshData, severity: Float) -> MeshData {
        var indices = mesh.indices
        let corruptCount = Int(Float(indices.count) * severity)
        
        for _ in 0..<corruptCount {
            let index = Int.random(in: 0..<indices.count)
            indices[index] = UInt32.random(in: UInt32(mesh.vertices.count)..<UInt32.max)
        }
        
        return MeshData(
            vertices: mesh.vertices,
            indices: indices,
            normals: mesh.normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
    
    private func injectNormalInconsistency(_ mesh: MeshData, severity: Float) -> MeshData {
        var normals = mesh.normals
        let corruptCount = Int(Float(normals.count) * severity)
        
        for _ in 0..<corruptCount {
            let index = Int.random(in: 0..<normals.count)
            normals[index] = normalize(SIMD3<Float>(
                .random(in: -1...1),
                .random(in: -1...1),
                .random(in: -1...1)
            ))
        }
        
        return MeshData(
            vertices: mesh.vertices,
            indices: mesh.indices,
            normals: normals,
            confidence: mesh.confidence,
            metadata: mesh.metadata
        )
    }
}

enum ErrorInjectionError: Error {
    case simulatedDeviceError
    case simulatedTimeout
    case simulatedMemoryPressure
    
    var localizedDescription: String {
        switch self {
        case .simulatedDeviceError:
            return "Simulated Metal device error"
        case .simulatedTimeout:
            return "Simulated operation timeout"
        case .simulatedMemoryPressure:
            return "Simulated memory pressure condition"
        }
    }
}