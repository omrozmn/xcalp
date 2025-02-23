import Foundation
import ComposableArchitecture
import CoreData

public struct ProcessingFeature: Reducer {
    public struct State: Equatable {
        public var isProcessing: Bool
        public var progress: Double
        public var currentOperation: ProcessingOperation?
        public var queuedOperations: [ProcessingOperation]
        public var offlineMode: Bool
        public var error: ProcessingError?
        public var availableStorage: UInt64?
        public var availableMemory: UInt64?
        public var backgroundTasks: [String: BackgroundTaskStatus]
        
        public init(
            isProcessing: Bool = false,
            progress: Double = 0.0,
            currentOperation: ProcessingOperation? = nil,
            queuedOperations: [ProcessingOperation] = [],
            offlineMode: Bool = false,
            error: ProcessingError? = nil,
            availableStorage: UInt64? = nil,
            availableMemory: UInt64? = nil,
            backgroundTasks: [String: BackgroundTaskStatus] = [:]
        ) {
            self.isProcessing = isProcessing
            self.progress = progress
            self.currentOperation = currentOperation
            self.queuedOperations = queuedOperations
            self.offlineMode = offlineMode
            self.error = error
            self.availableStorage = availableStorage
            self.availableMemory = availableMemory
            self.backgroundTasks = backgroundTasks
        }
    }
    
    public enum Action: Equatable {
        case processScannedData(Data)
        case processQueuedOperations
        case operationCompleted(ProcessingOperation)
        case operationFailed(ProcessingOperation, ProcessingError)
        case progressUpdated(Double)
        case toggleOfflineMode
        case syncWithServer
        case errorOccurred(ProcessingError)
        case dismissError
        case checkSystemResources
        case systemResourcesUpdated(storage: UInt64, memory: UInt64)
        case backgroundTaskStarted(String)
        case backgroundTaskCompleted(String)
        case backgroundTaskFailed(String, Error)
        case cancelBackgroundTasks
        case handleSyncConflict(ProcessingOperation)
        case retryOperation(ProcessingOperation)
    }
    
    @Dependency(\.processingClient) var processingClient
    @Dependency(\.offlineStorage) var offlineStorage
    @Dependency(\.backgroundTask) var backgroundTask
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .processScannedData(data):
                let operation = ProcessingOperation(
                    id: UUID(),
                    type: .scan,
                    data: data,
                    timestamp: Date()
                )
                
                return .run { [state] send in
                    // Check available resources
                    let storage = try await processingClient.checkAvailableStorage()
                    let memory = try await processingClient.checkAvailableMemory()
                    
                    await send(.systemResourcesUpdated(storage: storage, memory: memory))
                    
                    // Reserve extra space for processing
                    let requiredStorage = UInt64(Double(data.count) * 2.5) // 150% overhead
                    let requiredMemory = UInt64(Double(data.count) * 3) // 200% overhead
                    
                    if storage < requiredStorage {
                        await send(.errorOccurred(.storageLimitExceeded(available: storage)))
                        if state.offlineMode {
                            try await offlineStorage.storeOperation(operation)
                        }
                        return
                    }
                    
                    if memory < requiredMemory {
                        await send(.errorOccurred(.insufficientMemory(available: memory)))
                        if state.offlineMode {
                            try await offlineStorage.storeOperation(operation)
                        }
                        return
                    }
                    
                    // Start background processing with chunking
                    let taskName = "process_scan_\(operation.id.uuidString)"
                    let resources = TaskResources(
                        memory: requiredMemory,
                        storage: requiredStorage,
                        bandwidth: 0
                    )
                    
                    do {
                        let identifier = try await backgroundTask.beginTask(
                            taskName,
                            priority: .medium,
                            resources: resources
                        ) {
                            let input = ProcessingInput(id: operation.id, data: data)
                            let progress = try await processingClient.processData(input)
                            for await value in progress {
                                await send(.progressUpdated(value))
                            }
                        }
                        await send(.backgroundTaskStarted(identifier))
                    } catch {
                        if error is BackgroundTaskError {
                            // Queue for later if background task fails
                            try await offlineStorage.storeOperation(operation)
                            await send(.errorOccurred(.queueLimitExceeded))
                        } else {
                            await send(.errorOccurred(.processingFailed(error)))
                        }
                    }
                }
                
            case let .backgroundTaskStarted(identifier):
                state.backgroundTasks[identifier] = .running
                state.isProcessing = true
                return .none
                
            case let .backgroundTaskCompleted(identifier):
                state.backgroundTasks[identifier] = .completed
                state.isProcessing = !state.backgroundTasks.isEmpty
                return .none
                
            case let .backgroundTaskFailed(identifier, error):
                state.backgroundTasks[identifier] = .failed(error)
                state.isProcessing = !state.backgroundTasks.isEmpty
                return .send(.errorOccurred(.processingFailed(error)))
                
            case .cancelBackgroundTasks:
                return .run { _ in
                    await backgroundTask.cancelAllTasks()
                }
                
            case let .backgroundTaskExpired:
                if let operation = state.currentOperation {
                    return .send(.operationFailed(operation, .backgroundTaskExpired))
                }
                return .none
                
            case let .systemResourcesUpdated(storage, memory):
                state.availableStorage = storage
                state.availableMemory = memory
                return .none
                
            case .checkSystemResources:
                return .run { send in
                    let storage = try await processingClient.checkAvailableStorage()
                    let memory = try await processingClient.checkAvailableMemory()
                    await send(.systemResourcesUpdated(storage: storage, memory: memory))
                }
                
            case let .handleSyncConflict(operation):
                // Implement conflict resolution strategy
                return .none
                
            case let .retryOperation(operation):
                state.queuedOperations.append(operation)
                return .send(.processQueuedOperations)
                
            case .processQueuedOperations:
                guard !state.queuedOperations.isEmpty else { return .none }
                state.isProcessing = true
                return .run { [operations = state.queuedOperations] send in
                    for operation in operations {
                        do {
                            let progress = try await processingClient.processData(operation.data)
                            for await value in progress {
                                await send(.progressUpdated(value))
                            }
                            await send(.operationCompleted(operation))
                        } catch {
                            await send(.operationFailed(operation, .processingFailed(error)))
                            break
                        }
                    }
                }
                
            case let .operationCompleted(operation):
                state.isProcessing = false
                state.progress = 0
                state.currentOperation = nil
                state.queuedOperations.removeAll { $0.id == operation.id }
                return .run { _ in
                    try await offlineStorage.markOperationCompleted(operation)
                }
                
            case let .operationFailed(operation, error):
                state.isProcessing = false
                state.error = error
                if state.offlineMode {
                    state.queuedOperations.append(operation)
                }
                return .none
                
            case let .progressUpdated(progress):
                state.progress = progress
                return .none
                
            case .toggleOfflineMode:
                state.offlineMode.toggle()
                if !state.offlineMode {
                    return .send(.syncWithServer)
                }
                return .none
                
            case .syncWithServer:
                guard !state.queuedOperations.isEmpty else { return .none }
                return .send(.processQueuedOperations)
                
            case let .errorOccurred(error):
                state.error = error
                return .none
                
            case .dismissError:
                state.error = nil
                return .none
                
            default:
                return .none
            }
        }
    }
}

public enum ProcessingOperation: Equatable, Codable {
    case scan
    case analysis
    case export
    
    public var id: UUID
    public var type: ProcessingOperationType
    public var data: Data
    public var timestamp: Date
    
    public enum ProcessingOperationType: String, Codable {
        case scan
        case analysis
        case export
    }
}

public enum ProcessingError: Error, Equatable {
    case processingFailed(Error)
    case storageError(Error)
    case networkError(Error)
    case queueLimitExceeded
    case operationTimeout
    case insufficientMemory(available: UInt64)
    case backgroundTaskExpired
    case storageLimitExceeded(available: UInt64)
    case networkTimeout(operation: ProcessingOperation)
    case syncConflict(operation: ProcessingOperation)
    
    public static func == (lhs: ProcessingError, rhs: ProcessingError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
    
    public var localizedDescription: String {
        switch self {
        case .processingFailed(let error):
            return "Processing failed: \(error.localizedDescription)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .queueLimitExceeded:
            return "Operation queue limit exceeded"
        case .operationTimeout:
            return "Operation timed out"
        case .insufficientMemory(let available):
            return "Insufficient memory. Available: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory))"
        case .backgroundTaskExpired:
            return "Background task expired before completion"
        case .storageLimitExceeded(let available):
            return "Storage limit exceeded. Available: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file))"
        case .networkTimeout(let operation):
            return "Network timeout while processing \(operation.type.rawValue)"
        case .syncConflict(let operation):
            return "Sync conflict detected for \(operation.type.rawValue)"
        }
    }
}

public struct ProcessingInput: Equatable {
    public let id: UUID
    public let data: Data
}
