import Foundation
import ComposableArchitecture
import CoreML
import Vision

public struct AnalysisFeature: Reducer {
    public struct State: Equatable {
        // ...existing code...
    }
    
    public enum Action: Equatable {
        case selectAnalysisType(AnalysisType?)
        case startAnalysis
        case updateProgress(Double)
        case analysisCompleted([AnalysisResult])
        case setError(String?)
    }
    
    @Dependency(\.analysisClient) var analysisClient
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .selectAnalysisType(type):
                state.selectedAnalysisType = type
                return .none
                
            case .startAnalysis:
                guard let type = state.selectedAnalysisType else { return .none }
                state.isAnalyzing = true
                state.progress = 0.0
                state.errorMessage = nil
                
                return .run { [type] send in
                    let progressUpdates = await analysisClient.monitorProgress()
                    
                    for await progress in progressUpdates {
                        await send(.updateProgress(progress))
                    }
                    
                    do {
                        let results = try await performAnalysis(type: type)
                        await send(.analysisCompleted(results))
                    } catch {
                        await send(.setError(error.localizedDescription))
                    }
                }
                
            case let .updateProgress(progress):
                state.progress = progress
                return .none
                
            case let .analysisCompleted(results):
                state.isAnalyzing = false
                state.results = results
                return .none
                
            case let .setError(message):
                state.isAnalyzing = false
                state.errorMessage = message
                return .none
            }
        }
    }
    
    private func performAnalysis(type: AnalysisType) async throws -> [AnalysisResult] {
        switch type {
        case .densityMapping:
            return try await analysisClient.analyzeDensity()
        case .graftPlacement:
            return try await analysisClient.analyzeGraftPlacement()
        case .growthProjection:
            return try await analysisClient.analyzeGrowthProjection()
        }
    }
}

// MARK: - Analysis Client Interface
public struct AnalysisClient {
    public var monitorProgress: @Sendable () -> AsyncStream<Double>
    public var analyzeDensity: @Sendable () async throws -> [AnalysisFeature.AnalysisResult]
    public var analyzeGraftPlacement: @Sendable () async throws -> [AnalysisFeature.AnalysisResult]
    public var analyzeGrowthProjection: @Sendable () async throws -> [AnalysisFeature.AnalysisResult]
    
    public static let live = Self(
        monitorProgress: {
            AsyncStream { continuation in
                Task {
                    for i in 0...10 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continuation.yield(Double(i) / 10.0)
                    }
                    continuation.finish()
                }
            }
        },
        analyzeDensity: {
            try await performDensityAnalysis()
        },
        analyzeGraftPlacement: {
            try await performGraftPlacementAnalysis()
        },
        analyzeGrowthProjection: {
            try await performGrowthProjectionAnalysis()
        }
    )
}

// MARK: - Implementation Details
private func performDensityAnalysis() async throws -> [AnalysisFeature.AnalysisResult] {
    let config = MLModelConfiguration()
    config.computeUnits = .all
    
    let model = try HairDensityModel(configuration: config)
    let results = try await model.predictions(from: [/* input data */])
    
    return results.map { prediction in
        AnalysisFeature.AnalysisResult(
            type: .densityMapping,
            summary: "Region density: \(prediction.density) follicles/cm²"
        )
    }
}

private func performGraftPlacementAnalysis() async throws -> [AnalysisFeature.AnalysisResult] {
    let analyzer = GraftPlacementAnalyzer()
    let placements = try await analyzer.calculateOptimalPlacements()
    
    return placements.map { placement in
        AnalysisFeature.AnalysisResult(
            type: .graftPlacement,
            summary: "Optimal graft count: \(placement.graftCount), Coverage: \(Int(placement.coverage * 100))%"
        )
    }
}

private func performGrowthProjectionAnalysis() async throws -> [AnalysisFeature.AnalysisResult] {
    let projector = GrowthProjector()
    let projections = try await projector.calculateProjections(months: [3, 6, 12])
    
    return projections.map { projection in
        AnalysisFeature.AnalysisResult(
            type: .growthProjection,
            summary: "Month \(projection.month): Expected density \(projection.density) follicles/cm²"
        )
    }
}

// MARK: - Dependencies
extension DependencyValues {
    public var analysisClient: AnalysisClient {
        get { self[AnalysisClient.self] }
        set { self[AnalysisClient.self] = newValue }
    }
}

extension AnalysisClient: DependencyKey {
    public static let liveValue = AnalysisClient.live
    
    public static let testValue = Self(
        monitorProgress: { AsyncStream { $0.finish() } },
        analyzeDensity: { [] },
        analyzeGraftPlacement: { [] },
        analyzeGrowthProjection: { [] }
    )
}