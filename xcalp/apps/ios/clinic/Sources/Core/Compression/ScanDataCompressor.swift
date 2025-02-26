import Foundation
import Compression
import Metal
import CoreML

public actor ScanDataCompressor {
    private let compressionLevel: Float
    private let chunkSize: Int
    private let maxParallelOperations: Int
    private let processingQueue: DispatchQueue
    
    public init(
        compressionLevel: Float = AppConfiguration.Performance.Cache.compressionLevel,
        chunkSize: Int = 1024 * 1024, // 1MB chunks
        maxParallelOperations: Int = 4
    ) {
        self.compressionLevel = compressionLevel
        self.chunkSize = chunkSize
        self.maxParallelOperations = maxParallelOperations
        self.processingQueue = DispatchQueue(
            label: "com.xcalp.compression",
            qos: .utility,
            attributes: .concurrent
        )
    }
    
    public func compressMesh(_ mesh: OptimizedMesh) async throws -> CompressedMeshData {
        // Compress vertex data
        let compressedVertices = try await compressArray(
            mesh.vertices,
            algorithm: .lzfse
        )
        
        // Compress normal data
        let compressedNormals = try await compressArray(
            mesh.normals,
            algorithm: .lzfse
        )
        
        // Compress index data using a more efficient algorithm for integers
        let compressedIndices = try await compressArray(
            mesh.indices,
            algorithm: .lz4
        )
        
        return CompressedMeshData(
            vertices: compressedVertices,
            normals: compressedNormals,
            indices: compressedIndices,
            originalSize: MemoryLayout<SIMD3<Float>>.stride * mesh.vertices.count +
                        MemoryLayout<SIMD3<Float>>.stride * mesh.normals.count +
                        MemoryLayout<UInt32>.stride * mesh.indices.count
        )
    }
    
    public func decompressMesh(_ compressedData: CompressedMeshData) async throws -> OptimizedMesh {
        // Decompress vertex data
        let vertices: [SIMD3<Float>] = try await decompressArray(
            compressedData.vertices,
            algorithm: .lzfse
        )
        
        // Decompress normal data
        let normals: [SIMD3<Float>] = try await decompressArray(
            compressedData.normals,
            algorithm: .lzfse
        )
        
        // Decompress index data
        let indices: [UInt32] = try await decompressArray(
            compressedData.indices,
            algorithm: .lz4
        )
        
        return OptimizedMesh(
            vertices: vertices,
            normals: normals,
            indices: indices
        )
    }
    
    public func compressTexture(
        _ texture: ProcessedTexture,
        quality: AppConfiguration.Quality.Compression = .high
    ) async throws -> CompressedTextureData {
        let textureData = try await texture.texture.getPixelData()
        
        // Apply compression based on texture type
        let algorithm: CompressionAlgorithm
        switch texture.type {
        case .diffuse:
            // Use JPEG compression for diffuse textures
            let compressedImage = try await compressImage(
                textureData,
                width: texture.texture.width,
                height: texture.texture.height,
                quality: quality
            )
            return CompressedTextureData(
                data: compressedImage,
                type: texture.type,
                width: texture.texture.width,
                height: texture.texture.height,
                originalSize: textureData.count
            )
            
        case .normal:
            // Use lossless compression for normal maps
            algorithm = .lzfse
        case .occlusion:
            // Use fast compression for occlusion maps
            algorithm = .lz4
        }
        
        let compressedData = try await compressData(
            textureData,
            algorithm: algorithm
        )
        
        return CompressedTextureData(
            data: compressedData,
            type: texture.type,
            width: texture.texture.width,
            height: texture.texture.height,
            originalSize: textureData.count
        )
    }
    
    public func decompressTexture(
        _ compressedData: CompressedTextureData
    ) async throws -> Data {
        switch compressedData.type {
        case .diffuse:
            // Decompress JPEG data
            return compressedData.data
        case .normal, .occlusion:
            // Decompress using appropriate algorithm
            let algorithm: CompressionAlgorithm = compressedData.type == .normal ? .lzfse : .lz4
            return try await decompressData(
                compressedData.data,
                algorithm: algorithm
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func compressArray<T>(_ array: [T], algorithm: CompressionAlgorithm) async throws -> Data {
        let data = Data(bytes: array, count: array.count * MemoryLayout<T>.stride)
        return try await compressData(data, algorithm: algorithm)
    }
    
    private func decompressArray<T>(_ data: Data, algorithm: CompressionAlgorithm) async throws -> [T] {
        let decompressedData = try await decompressData(data, algorithm: algorithm)
        let count = decompressedData.count / MemoryLayout<T>.stride
        return decompressedData.withUnsafeBytes { pointer in
            Array(UnsafeBufferPointer(
                start: pointer.baseAddress?.assumingMemoryBound(to: T.self),
                count: count
            ))
        }
    }
    
    private func compressData(_ data: Data, algorithm: CompressionAlgorithm) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                do {
                    var compressedData = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.chunkSize)
                    defer { buffer.deallocate() }
                    
                    var stream = compression_stream()
                    var status = compression_stream_init(
                        &stream,
                        COMPRESSION_STREAM_ENCODE,
                        algorithm.rawValue
                    )
                    guard status == COMPRESSION_STATUS_OK else {
                        throw CompressionError.initializationFailed
                    }
                    defer { compression_stream_destroy(&stream) }
                    
                    // Process data in chunks
                    data.withUnsafeBytes { inputPtr in
                        var input = inputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        var inputSize = data.count
                        
                        repeat {
                            stream.src_ptr = input
                            stream.src_size = min(inputSize, self.chunkSize)
                            stream.dst_ptr = buffer
                            stream.dst_size = self.chunkSize
                            
                            let flags = inputSize <= self.chunkSize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                            status = compression_stream_process(&stream, flags)
                            
                            if status == COMPRESSION_STATUS_ERROR {
                                continuation.resume(throwing: CompressionError.compressionFailed)
                                return
                            }
                            
                            let compressedBytes = self.chunkSize - stream.dst_size
                            compressedData.append(buffer, count: compressedBytes)
                            
                            input? += self.chunkSize
                            inputSize -= self.chunkSize
                        } while status == COMPRESSION_STATUS_OK
                    }
                    
                    continuation.resume(returning: compressedData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func decompressData(_ data: Data, algorithm: CompressionAlgorithm) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                do {
                    var decompressedData = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.chunkSize)
                    defer { buffer.deallocate() }
                    
                    var stream = compression_stream()
                    var status = compression_stream_init(
                        &stream,
                        COMPRESSION_STREAM_DECODE,
                        algorithm.rawValue
                    )
                    guard status == COMPRESSION_STATUS_OK else {
                        throw CompressionError.initializationFailed
                    }
                    defer { compression_stream_destroy(&stream) }
                    
                    // Process data in chunks
                    data.withUnsafeBytes { inputPtr in
                        var input = inputPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        var inputSize = data.count
                        
                        repeat {
                            stream.src_ptr = input
                            stream.src_size = min(inputSize, self.chunkSize)
                            stream.dst_ptr = buffer
                            stream.dst_size = self.chunkSize
                            
                            let flags = inputSize <= self.chunkSize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                            status = compression_stream_process(&stream, flags)
                            
                            if status == COMPRESSION_STATUS_ERROR {
                                continuation.resume(throwing: CompressionError.decompressionFailed)
                                return
                            }
                            
                            let decompressedBytes = self.chunkSize - stream.dst_size
                            decompressedData.append(buffer, count: decompressedBytes)
                            
                            input? += self.chunkSize
                            inputSize -= self.chunkSize
                        } while status == COMPRESSION_STATUS_OK
                    }
                    
                    continuation.resume(returning: decompressedData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func compressImage(
        _ imageData: Data,
        width: Int,
        height: Int,
        quality: AppConfiguration.Quality.Compression
    ) async throws -> Data {
        guard let image = CIImage(data: imageData) else {
            throw CompressionError.imageProcessingFailed
        }
        
        let context = CIContext()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                if let compressedData = context.jpegRepresentation(
                    of: image,
                    colorSpace: colorSpace,
                    options: [
                        .compressionQuality: quality.compressionFactor
                    ]
                ) {
                    continuation.resume(returning: compressedData)
                } else {
                    continuation.resume(throwing: CompressionError.imageCompressionFailed)
                }
            }
        }
    }
}

// MARK: - Supporting Types

public enum CompressionAlgorithm {
    case lzfse
    case lz4
    case zlib
    
    var rawValue: compression_algorithm {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .lz4: return COMPRESSION_LZ4
        case .zlib: return COMPRESSION_ZLIB
        }
    }
}

public struct CompressedMeshData {
    public let vertices: Data
    public let normals: Data
    public let indices: Data
    public let originalSize: Int
    
    public var compressedSize: Int {
        vertices.count + normals.count + indices.count
    }
    
    public var compressionRatio: Float {
        Float(compressedSize) / Float(originalSize)
    }
}

public struct CompressedTextureData {
    public let data: Data
    public let type: ProcessedTexture.TextureType
    public let width: Int
    public let height: Int
    public let originalSize: Int
    
    public var compressionRatio: Float {
        Float(data.count) / Float(originalSize)
    }
}

public enum CompressionError: Error {
    case initializationFailed
    case compressionFailed
    case decompressionFailed
    case imageProcessingFailed
    case imageCompressionFailed
}