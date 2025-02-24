import ComposableArchitecture
import CoreImage
import Dependencies
import Foundation
import Metal

public struct ProcessingClient {
    public var processData: @Sendable (ProcessingInput) async throws -> AsyncStream<Double>
    public var checkAvailableStorage: @Sendable () async throws -> UInt64
    public var checkAvailableMemory: @Sendable () async throws -> UInt64
    
    public static let liveValue = Self.live
    
    static let live = Self(
        processData: { input in
            AsyncStream { continuation in
                Task {
                    do {
                        // Use cache for processed data if available
                        let cacheKey = "processed_\(input.id.uuidString)"
                        if let cachedData = try? CacheManager.shared.retrieve(cacheKey) {
                            continuation.yield(1.0)
                            continuation.finish()
                            return
                        }
                        
                        // Process in chunks for better memory management
                        let chunkSize = 1024 * 1024 // 1MB chunks
                        let totalChunks = (input.data.count + chunkSize - 1) / chunkSize
                        
                        var processedData = Data()
                        for chunk in 0..<totalChunks {
                            let start = chunk * chunkSize
                            let end = min(start + chunkSize, input.data.count)
                            let chunkData = input.data[start..<end]
                            
                            // Process chunk
                            let processor = MeshProcessor.shared
                            let processedChunk = try await processor.processMesh(Data(chunkData))
                            processedData.append(processedChunk.data)
                            
                            let progress = Double(chunk + 1) / Double(totalChunks)
                            continuation.yield(progress)
                        }
                        
                        // Cache processed result
                        try CacheManager.shared.store(processedData, forKey: cacheKey)
                        continuation.finish()
                    } catch {
                        continuation.finish()
                        throw error
                    }
                }
            }
        },
        checkAvailableStorage: {
            let fileManager = FileManager.default
            guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let freeSize = systemAttributes[.systemFreeSize] as? UInt64 else {
                return 0
            }
            return freeSize
        },
        checkAvailableMemory: {
            let memoryUsage = ProcessInfo.processInfo.physicalMemory
            let usedMemory = mach_task_self_.memoryUsage()
            return memoryUsage - usedMemory
        }
    )
    
    public static let testValue = Self(
        processData: { _ in
            AsyncStream { continuation in
                continuation.yield(1.0)
                continuation.finish()
            }
        }
    )
}

extension DependencyValues {
    public var processingClient: ProcessingClient {
        get { self[ProcessingClient.self] }
        set { self[ProcessingClient.self] = newValue }
    }
}
