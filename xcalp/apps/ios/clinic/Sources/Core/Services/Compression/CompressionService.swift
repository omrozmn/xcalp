import Foundation
import Compression
import os.log

public enum CompressionError: Error, LocalizedError {
    case compressionFailed
    case decompressionFailed
    case invalidData
    case bufferTooSmall
    
    public var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress data"
        case .decompressionFailed:
            return "Failed to decompress data"
        case .invalidData:
            return "Invalid data format"
        case .bufferTooSmall:
            return "Buffer size too small for operation"
        }
    }
}

public final class CompressionService {
    public static let shared = CompressionService()
    
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "Compression")
    private let algorithm: compression_algorithm = COMPRESSION_LZFSE
    private let streamSize = 64 * 1024  // 64KB chunks
    private let compressionQueue = DispatchQueue(label: "com.xcalp.clinic.compression", qos: .userInitiated)
    
    private init() {}
    
    /// Compress data using LZFSE algorithm
    /// - Parameter data: Data to compress
    /// - Returns: Compressed data
    public func compress(_ data: Data) throws -> Data {
        let sourceSize = data.count
        let destinationSize = sourceSize * 2  // Conservative estimate
        
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            guard let baseAddress = sourceBuffer.baseAddress else {
                return 0
            }
            
            return compression_encode_buffer(
                destination,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                algorithm
            )
        }
        
        guard compressedSize > 0 else {
            logger.error("Compression failed: \(sourceSize) bytes")
            throw CompressionError.compressionFailed
        }
        
        logger.info("Compressed \(sourceSize) bytes to \(compressedSize) bytes")
        return Data(bytes: destination, count: compressedSize)
    }
    
    /// Decompress data using LZFSE algorithm
    /// - Parameter data: Compressed data
    /// - Returns: Original data
    public func decompress(_ data: Data) throws -> Data {
        let sourceSize = data.count
        let destinationSize = sourceSize * 4  // Conservative estimate
        
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        
        let decompressedSize = data.withUnsafeBytes { sourceBuffer in
            guard let baseAddress = sourceBuffer.baseAddress else {
                return 0
            }
            
            return compression_decode_buffer(
                destination,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                algorithm
            )
        }
        
        guard decompressedSize > 0 else {
            logger.error("Decompression failed: \(sourceSize) bytes")
            throw CompressionError.decompressionFailed
        }
        
        logger.info("Decompressed \(sourceSize) bytes to \(decompressedSize) bytes")
        return Data(bytes: destination, count: decompressedSize)
    }
    
    /// Stream compress large data
    /// - Parameter data: Data to compress
    /// - Returns: Compressed data chunks
    public func streamCompress(_ data: Data) throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let totalSize = data.count
            var offset = 0
            
            Task {
                do {
                    while offset < totalSize {
                        let chunkSize = min(streamSize, totalSize - offset)
                        let chunk = data[offset..<(offset + chunkSize)]
                        let compressedChunk = try compress(Data(chunk))
                        
                        continuation.yield(compressedChunk)
                        offset += chunkSize
                        
                        // Add small delay to prevent overwhelming the system
                        try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Stream decompress large data
    /// - Parameter data: Compressed data
    /// - Returns: Original data chunks
    public func streamDecompress(_ data: Data) throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let totalSize = data.count
            var offset = 0
            
            Task {
                do {
                    while offset < totalSize {
                        let chunkSize = min(streamSize, totalSize - offset)
                        let chunk = data[offset..<(offset + chunkSize)]
                        let decompressedChunk = try decompress(Data(chunk))
                        
                        continuation.yield(decompressedChunk)
                        offset += chunkSize
                        
                        // Add small delay to prevent overwhelming the system
                        try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func compressData(_ data: Data) throws -> Data {
        let sourceSize = data.count
        let destinationSize = sourceSize + 64 * 1024  // Add 64KB safety buffer
        
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { source in
            compression_encode_buffer(
                destination,
                destinationSize,
                source.bindMemory(to: UInt8.self).baseAddress!,
                sourceSize,
                nil,
                algorithm
            )
        }
        
        guard compressedSize > 0 else {
            throw CompressionError.compressionFailed
        }
        
        return Data(bytes: destination, count: compressedSize)
    }
    
    public func decompressData(_ data: Data, expectedSize: Int) throws -> Data {
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destination.deallocate() }
        
        let decompressedSize = data.withUnsafeBytes { source in
            compression_decode_buffer(
                destination,
                expectedSize,
                source.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                algorithm
            )
        }
        
        guard decompressedSize == expectedSize else {
            throw CompressionError.decompressionFailed
        }
        
        return Data(bytes: destination, count: decompressedSize)
    }
}

// MARK: - Dependency Interface

public struct CompressionClient {
    public var compress: (Data) throws -> Data
    public var decompress: (Data) throws -> Data
    public var streamCompress: (Data) throws -> AsyncThrowingStream<Data, Error>
    public var streamDecompress: (Data) throws -> AsyncThrowingStream<Data, Error>
    
    public init(
        compress: @escaping (Data) throws -> Data,
        decompress: @escaping (Data) throws -> Data,
        streamCompress: @escaping (Data) throws -> AsyncThrowingStream<Data, Error>,
        streamDecompress: @escaping (Data) throws -> AsyncThrowingStream<Data, Error>
    ) {
        self.compress = compress
        self.decompress = decompress
        self.streamCompress = streamCompress
        self.streamDecompress = streamDecompress
    }
}

extension CompressionClient {
    public static let live = Self(
        compress: { try CompressionService.shared.compress($0) },
        decompress: { try CompressionService.shared.decompress($0) },
        streamCompress: { try CompressionService.shared.streamCompress($0) },
        streamDecompress: { try CompressionService.shared.streamDecompress($0) }
    )
    
    public static let test = Self(
        compress: { $0 },
        decompress: { $0 },
        streamCompress: { data in
            AsyncThrowingStream { continuation in
                continuation.yield(data)
                continuation.finish()
            }
        },
        streamDecompress: { data in
            AsyncThrowingStream { continuation in
                continuation.yield(data)
                continuation.finish()
            }
        }
    )
}
