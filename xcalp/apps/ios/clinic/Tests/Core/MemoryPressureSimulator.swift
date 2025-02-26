import Foundation

final class MemoryPressureSimulator {
    private var memoryBlocks: [Data] = []
    private let pressureLevels: [Double] = [0.25, 0.5, 0.75, 0.9]
    private var currentPressureLevel: Int = 0
    
    func simulateMemoryPressure(level: Int, during operation: () async throws -> Void) async throws {
        guard level >= 0 && level < pressureLevels.count else {
            throw MemoryError.invalidPressureLevel
        }
        
        // Calculate target memory usage
        let targetPressure = pressureLevels[level]
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let targetUsage = UInt64(Double(availableMemory) * targetPressure)
        
        // Allocate memory to reach target pressure
        try allocateMemory(targetBytes: targetUsage)
        
        defer {
            // Release memory pressure
            memoryBlocks.removeAll()
        }
        
        // Execute operation under memory pressure
        try await operation()
    }
    
    func runUnderMemoryPressure<T>(
        _ operation: () async throws -> T,
        pressureLevel: Int,
        timeout: TimeInterval
    ) async throws -> T {
        return try await withTimeout(seconds: timeout) {
            try await simulateMemoryPressure(level: pressureLevel) {
                try await operation()
            }
            return try await operation()
        }
    }
    
    private func allocateMemory(targetBytes: UInt64) throws {
        let blockSize = 1024 * 1024 // 1MB blocks
        let numBlocks = Int(targetBytes / UInt64(blockSize))
        
        for _ in 0..<numBlocks {
            guard let block = try? Data(count: blockSize) else {
                throw MemoryError.allocationFailed
            }
            memoryBlocks.append(block)
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MemoryError.timeout
            }
            
            // Add operation task
            group.addTask {
                return try await operation()
            }
            
            // Return first completed result or throw first error
            return try await group.next() ?? { throw MemoryError.operationFailed }()
        }
    }
}

enum MemoryError: Error {
    case invalidPressureLevel
    case allocationFailed
    case timeout
    case operationFailed
    
    var localizedDescription: String {
        switch self {
        case .invalidPressureLevel:
            return "Invalid memory pressure level specified"
        case .allocationFailed:
            return "Failed to allocate memory for pressure simulation"
        case .timeout:
            return "Operation timed out under memory pressure"
        case .operationFailed:
            return "Operation failed under memory pressure"
        }
    }
}

extension MemoryPressureSimulator {
    static func megabytesToBytes(_ mb: Int) -> UInt64 {
        return UInt64(mb) * 1024 * 1024
    }
    
    static func bytesToMegabytes(_ bytes: UInt64) -> Double {
        return Double(bytes) / (1024 * 1024)
    }
}