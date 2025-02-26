import ARKit
import Combine
import CoreHaptics
import RealityKit
import SwiftUI
import ComposableArchitecture
import Foundation

public struct ScanningFeature: Reducer {
    public struct State: Equatable {
        var isScanning: Bool = false
        var scanningMode: ScanningMode = .lidar
        var scanningStatus: ScanningStatus = .ready
        var scanningProgress: Double = 0
        var currentQuality: QualityAssessment?
        var error: ScanningError?
        var currentSession: UUID?
        
        public init() {}
    }
    
    public enum Action: Equatable {
        case onAppear
        case startScanningTapped
        case stopScanningTapped
        case scanningModeChanged(ScanningMode)
        case frameProcessed(FrameProcessingResult)
        case qualityUpdated(QualityAssessment)
        case progressUpdated(Double)
        case scanningFailed(ScanningError)
        case dismissError
    }
    
    @Dependency(\.scanningClient) var scanningClient
    
    public init() {}
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
                
            case .startScanningTapped:
                state.isScanning = true
                state.scanningStatus = .initializing
                state.currentSession = UUID()
                state.scanningProgress = 0
                state.error = nil
                
                return .run { [mode = state.scanningMode] send in
                    do {
                        let config = ScanningConfiguration()
                        try await scanningClient.startNewSession(
                            mode: mode,
                            configuration: config
                        )
                    } catch {
                        await send(.scanningFailed(error as? ScanningError ?? .unrecoverableError))
                    }
                }
                
            case .stopScanningTapped:
                state.isScanning = false
                state.scanningStatus = .completed
                return .none
                
            case .scanningModeChanged(let mode):
                guard !state.isScanning else { return .none }
                state.scanningMode = mode
                return .none
                
            case let .frameProcessed(result):
                state.currentQuality = result.quality
                state.scanningStatus = .scanning
                
                // Update progress based on surface completeness
                let progress = result.quality.surfaceCompleteness
                return .send(.progressUpdated(progress))
                
            case let .qualityUpdated(quality):
                state.currentQuality = quality
                return .none
                
            case let .progressUpdated(progress):
                state.scanningProgress = progress
                return .none
                
            case let .scanningFailed(error):
                state.error = error
                state.scanningStatus = .failed(error)
                state.isScanning = false
                return .none
                
            case .dismissError:
                state.error = nil
                return .none
            }
        }
    }
}

// MARK: - Dependencies
extension DependencyValues {
    var scanningClient: ScanningClient {
        get { self[ScanningClient.self] }
        set { self[ScanningClient.self] = newValue }
    }
}

struct ScanningClient {
    var startNewSession: @Sendable (ScanningMode, ScanningConfiguration) async throws -> Void
    var processFrame: @Sendable (ARFrame) async throws -> FrameProcessingResult
    var stopSession: @Sendable () async -> Void
}

extension ScanningClient: DependencyKey {
    static let liveValue = ScanningClient(
        startNewSession: { mode, config in
            let coordinator = try await ScanningSystemCoordinator(device: MTLCreateSystemDefaultDevice()!)
            try await coordinator.startNewSession(mode: mode, configuration: config)
        },
        processFrame: { frame in
            let coordinator = try await ScanningSystemCoordinator(device: MTLCreateSystemDefaultDevice()!)
            return try await coordinator.processFrame(frame)
        },
        stopSession: {
            // Implement session cleanup
        }
    )
}
