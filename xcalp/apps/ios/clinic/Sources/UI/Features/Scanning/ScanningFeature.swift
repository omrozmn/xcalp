import Foundation
import ComposableArchitecture
import ARKit
import RealityKit

public struct ScanningFeature: Reducer {
    public struct State: Equatable {
        public var isScanning: Bool
        public var scanQuality: ScanQuality
        public var lidarStatus: LidarStatus
        public var voiceGuidanceEnabled: Bool
        public var currentGuide: ScanningGuide?
        public var error: ScanningError?
        public var retryAttempt: Int
        public var maxRetries: Int
        
        public init(
            isScanning: Bool = false,
            scanQuality: ScanQuality = .unknown,
            lidarStatus: LidarStatus = .unknown,
            voiceGuidanceEnabled: Bool = true,
            currentGuide: ScanningGuide? = nil,
            error: ScanningError? = nil,
            retryAttempt: Int = 0,
            maxRetries: Int = 3
        ) {
            self.isScanning = isScanning
            self.scanQuality = scanQuality
            self.lidarStatus = lidarStatus
            self.voiceGuidanceEnabled = voiceGuidanceEnabled
            self.currentGuide = currentGuide
            self.error = error
            self.retryAttempt = retryAttempt
            self.maxRetries = maxRetries
        }
    }
    
    public enum Action: Equatable {
        case onAppear
        case checkDeviceCapabilities
        case deviceCapabilitiesResult(TaskResult<Bool>)
        case toggleVoiceGuidance
        case startScanning
        case stopScanning
        case scanQualityUpdated(ScanQuality)
        case lidarStatusUpdated(LidarStatus)
        case guideUpdated(ScanningGuide?)
        case captureButtonTapped
        case scanCaptured(TaskResult<Data>)
        case errorOccurred(ScanningError)
        case dismissError
        case retryInitialization
        case initializationCompleted
    }
    
    @Dependency(\.scanningClient) var scanningClient
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.checkDeviceCapabilities)
                
            case .checkDeviceCapabilities:
                state.lidarStatus = .initializing
                return .run { send in
                    await send(.deviceCapabilitiesResult(
                        TaskResult { try await scanningClient.checkDeviceCapabilities() }
                    ))
                }
                
            case let .deviceCapabilitiesResult(.success(isCapable)):
                if !isCapable {
                    state.error = .captureSetupFailed
                    state.lidarStatus = .failed
                    return .none
                }
                return .run { send in
                    for await status in scanningClient.monitorLidarStatus() {
                        await send(.lidarStatusUpdated(status))
                    }
                }
                
            case let .deviceCapabilitiesResult(.failure(error)):
                state.error = .initializationFailed(error.localizedDescription)
                state.lidarStatus = .failed
                return .none
                
            case let .lidarStatusUpdated(status):
                state.lidarStatus = status
                switch status {
                case .error(let error):
                    if state.retryAttempt < state.maxRetries {
                        state.retryAttempt += 1
                        state.lidarStatus = .retrying(state.retryAttempt, state.maxRetries)
                        return .send(.retryInitialization)
                    } else {
                        state.error = .initializationFailed(error.localizedDescription)
                        state.lidarStatus = .failed
                    }
                case .ready:
                    state.error = nil
                    state.retryAttempt = 0
                case .failed:
                    if state.error == nil {
                        state.error = .initializationFailed("Maximum retry attempts reached")
                    }
                default:
                    break
                }
                return .none
                
            case .retryInitialization:
                return .run { send in
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(state.retryAttempt))) * 1_000_000_000)
                    await send(.checkDeviceCapabilities)
                }
                
            case .toggleVoiceGuidance:
                state.voiceGuidanceEnabled.toggle()
                return .none
                
            case .startScanning:
                state.isScanning = true
                return .run { send in
                    for try await quality in scanningClient.monitorScanQuality() {
                        await send(.scanQualityUpdated(quality))
                    }
                }
                
            case .stopScanning:
                state.isScanning = false
                return .cancel()
                
            case let .scanQualityUpdated(quality):
                state.scanQuality = quality
                return .none
                
            case let .guideUpdated(guide):
                state.currentGuide = guide
                return .none
                
            case .captureButtonTapped:
                return .run { send in
                    await send(.scanCaptured(
                        TaskResult { try await scanningClient.captureScan() }
                    ))
                }
                
            case .scanCaptured(.success):
                state.isScanning = false
                return .none
                
            case .scanCaptured(.failure):
                return .send(.errorOccurred(.captureFailed))
                
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

// MARK: - Supporting Types
extension ScanningFeature {
    public enum ScanQuality: Equatable {
        case unknown
        case poor
        case fair
        case good
        case excellent
    }
    
    public enum LidarStatus: Equatable {
        case unknown
        case initializing
        case ready
        case error(Error)
        case failed
        case retrying(Int, Int) // current attempt, max attempts
    }
    
    public enum ScanningGuide: Equatable {
        case moveCloser
        case moveFarther
        case moveSlower
        case holdSteady
        case scanComplete
    }
    
    public enum ScanningError: Error, Equatable {
        case captureSetupFailed
        case noMeshDataAvailable
        case timeout
        case trackingFailed(String)
        case initializationFailed(String)
        case captureFailed
        case deviceNotCapable
        case deviceCheckFailed
        case insufficientLighting
        case excessiveMotion
        case scanProcessingFailed
        
        public var localizedDescription: String {
            switch self {
            case .captureSetupFailed:
                return "Failed to set up the scanning system"
            case .noMeshDataAvailable:
                return "No 3D mesh data was captured"
            case .timeout:
                return "Operation timed out"
            case .trackingFailed(let reason):
                return "Tracking failed: \(reason)"
            case .initializationFailed(let reason):
                return "LiDAR initialization failed: \(reason)"
            case .captureFailed:
                return "Failed to capture scan"
            case .deviceNotCapable:
                return "This device does not support 3D scanning"
            case .deviceCheckFailed:
                return "Failed to check device capabilities"
            case .insufficientLighting:
                return "The environment is too dark"
            case .excessiveMotion:
                return "Please move the device more slowly"
            case .scanProcessingFailed:
                return "Failed to process the scan"
            }
        }
    }
}
