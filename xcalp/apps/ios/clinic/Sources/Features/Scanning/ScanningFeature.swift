import SwiftUI
import ARKit
import RealityKit
import Combine
import CoreHaptics

public struct ScanningFeature: ReducerProtocol {
    public struct State: Equatable {
        var scanStatus: ScanStatus = .idle
        var scanQuality: Float = 0.0
        var isLiDARAvailable: Bool = false
        var scanProgress: Double = 0.0
        var currentError: ScanError?
        var meshQualityMetrics: MeshQualityMetrics = .init()
        var scanHistory: [ScanHistoryEntry] = []
        var hapticEngine: CHHapticEngine?
        var guidanceMessage: String?
    }
    
    public struct MeshQualityMetrics: Equatable {
        var coverage: Float = 0.0
        var density: Float = 0.0
        var stability: Float = 0.0
        var lighting: Float = 0.0
    }
    
    public struct ScanHistoryEntry: Equatable, Identifiable {
        let id: UUID
        let timestamp: Date
        let quality: Float
        let preview: Data?
    }
    
    public enum Action: Equatable {
        case onAppear
        case startScan
        case stopScan
        case updateQuality(Float)
        case updateProgress(Double)
        case scanCompleted(Result<ScanData, ScanError>)
        case updateMeshMetrics(MeshQualityMetrics)
        case updateGuidance(String)
        case saveScanToHistory(ScanHistoryEntry)
        case provideFeedback(FeedbackType)
    }
    
    public enum ScanStatus: Equatable {
        case idle
        case scanning
        case processing
        case completed
        case error(String)
    }
    
    public enum ScanError: Error, Equatable {
        case deviceNotSupported
        case insufficientLighting
        case excessiveMotion
        case processingFailed
    }
    
    public enum FeedbackType: Equatable {
        case success
        case warning
        case error
        case guidance
    }
    
    @Dependency(\.arSession) var arSession
    @Dependency(\.meshProcessor) var meshProcessor
    @Dependency(\.scanHistoryManager) var historyManager
    
    public var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
                return .none
                
            case .startScan:
                guard state.isLiDARAvailable else {
                    state.scanStatus = .error("Device does not support LiDAR scanning")
                    return .none
                }
                state.scanStatus = .scanning
                return startARSession()
                
            case .stopScan:
                state.scanStatus = .processing
                return processScanData()
                
            case .updateQuality(let quality):
                state.scanQuality = quality
                return .none
                
            case .updateProgress(let progress):
                state.scanProgress = progress
                return .none
                
            case .scanCompleted(.success):
                state.scanStatus = .completed
                return .none
                
            case .scanCompleted(.failure(let error)):
                state.scanStatus = .error(error.localizedDescription)
                state.currentError = error
                return .none
                
            case .updateMeshMetrics(let metrics):
                state.meshQualityMetrics = metrics
                if metrics.coverage < 0.7 {
                    return .send(.provideFeedback(.warning))
                }
                return .none
                
            case .updateGuidance(let message):
                state.guidanceMessage = message
                return .send(.provideFeedback(.guidance))
                
            case .saveScanToHistory(let entry):
                state.scanHistory.append(entry)
                return .none
                
            case .provideFeedback(let type):
                return provideFeedback(type)
            }
        }
    }
    
    private func startARSession() -> Effect<Action, Never> {
        Effect.run { send in
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .mesh
            config.environmentTexturing = .automatic
            
            arSession.run(config)
            
            Task {
                for await frame in arSession.meshFrameUpdates {
                    let metrics = analyzeMeshQuality(frame)
                    await send(.updateMeshMetrics(metrics))
                    await send(.updateGuidance(generateGuidance(from: metrics)))
                }
            }
            
            return .none
        }
    }
    
    private func processScanData() -> Effect<Action, Never> {
        Effect.run { send in
            do {
                let meshData = try await meshProcessor.processMesh(from: arSession)
                await send(.scanCompleted(.success(meshData)))
            } catch {
                await send(.scanCompleted(.failure(.processingFailed)))
            }
            return .none
        }
    }
    
    private func analyzeMeshQuality(_ frame: ARFrame) -> MeshQualityMetrics {
        var metrics = MeshQualityMetrics()
        
        metrics.density = calculateMeshDensity(frame.meshAnchors)
        metrics.lighting = frame.lightEstimate?.ambientIntensity ?? 0
        metrics.coverage = calculateCoverage(frame.meshAnchors)
        metrics.stability = calculateStability(frame.camera.trackingState)
        
        return metrics
    }
    
    private func generateGuidance(from metrics: MeshQualityMetrics) -> String {
        if metrics.lighting < 0.3 {
            return "Move to a better lit area"
        }
        if metrics.coverage < 0.7 {
            return "Move around to capture more angles"
        }
        if metrics.stability < 0.5 {
            return "Hold device more steady"
        }
        return "Scan quality is good"
    }
    
    private func provideFeedback(_ type: FeedbackType) -> Effect<Action, Never> {
        Effect.run { _ in
            guard let engine = try? CHHapticEngine() else { return }
            
            let intensity: Float
            let sharpness: Float
            
            switch type {
            case .success:
                intensity = 0.6
                sharpness = 0.5
            case .warning:
                intensity = 0.8
                sharpness = 0.7
            case .error:
                intensity = 1.0
                sharpness = 1.0
            case .guidance:
                intensity = 0.3
                sharpness = 0.3
            }
            
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0
            )
            
            try? engine.start()
            let pattern = try? CHHapticPattern(events: [event], parameters: [])
            try? engine.makePlayer(with: pattern!).start(atTime: 0)
        }
    }
    
    private func calculateMeshDensity(_ anchors: [ARMeshAnchor]) -> Float {
        let totalVertices = anchors.reduce(0) { $0 + $1.geometry.vertices.count }
        let totalArea = anchors.reduce(0.0) { $0 + calculateMeshArea($1) }
        return Float(totalVertices) / max(Float(totalArea), 1.0)
    }
    
    private func calculateCoverage(_ anchors: [ARMeshAnchor]) -> Float {
        let bounds = calculateMeshBounds(anchors)
        let volume = bounds.width * bounds.height * bounds.depth
        return min(Float(volume) / 1000.0, 1.0)
    }
    
    private func calculateStability(_ trackingState: ARCamera.TrackingState) -> Float {
        switch trackingState {
        case .normal:
            return 1.0
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return 0.3
            case .initializing:
                return 0.5
            default:
                return 0.7
            }
        default:
            return 0.0
        }
    }
}