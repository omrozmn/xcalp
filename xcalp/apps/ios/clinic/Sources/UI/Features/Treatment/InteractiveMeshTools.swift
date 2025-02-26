import Combine
import CoreGraphics
import Foundation
import RealityKit
import simd

public final class InteractiveMeshTools {
    private var selectedAreas: [UUID: SelectedArea] = [:]
    private let graftCalculator: GraftCalculator
    private let measurementSystem: MeasurementSystem
    private var subscribers: Set<AnyCancellable> = []
    
    public init(
        graftCalculator: GraftCalculator = GraftCalculator(),
        measurementSystem: MeasurementSystem = MeasurementSystem()
    ) {
        self.graftCalculator = graftCalculator
        self.measurementSystem = measurementSystem
    }
    
    public func startBrushStroke(at position: SIMD3<Float>, brushSize: Float = 1.0) -> UUID {
        let id = UUID()
        selectedAreas[id] = SelectedArea(
            id: id,
            initialPosition: position,
            brushSize: brushSize,
            points: [position]
        )
        return id
    }
    
    public func continueBrushStroke(_ id: UUID, to position: SIMD3<Float>) {
        guard var area = selectedAreas[id] else { return }
        area.points.append(position)
        selectedAreas[id] = area
        
        // Trigger real-time updates
        updateGraftCalculations(for: id)
    }
    
    public func endBrushStroke(_ id: UUID) async throws -> AreaMetrics {
        guard let area = selectedAreas[id] else {
            throw MeasurementError.invalidRegion("Area not found")
        }
        
        let metrics = try await calculateAreaMetrics(area)
        NotificationCenter.default.post(
            name: .areaMetricsUpdated,
            object: nil,
            userInfo: ["metrics": metrics]
        )
        
        return metrics
    }
    
    public func colorArea(_ id: UUID, with color: CGColor) {
        guard var area = selectedAreas[id] else { return }
        area.color = color
        selectedAreas[id] = area
        
        NotificationCenter.default.post(
            name: .areaColorChanged,
            object: nil,
            userInfo: ["id": id, "color": color]
        )
    }
    
    private func updateGraftCalculations(for areaId: UUID) {
        guard let area = selectedAreas[areaId] else { return }
        
        Task {
            do {
                let metrics = try await calculateAreaMetrics(area)
                NotificationCenter.default.post(
                    name: .graftCalculationsUpdated,
                    object: nil,
                    userInfo: ["metrics": metrics]
                )
            } catch {
                print("Failed to update graft calculations: \(error)")
            }
        }
    }
    
    private func calculateAreaMetrics(_ area: SelectedArea) async throws -> AreaMetrics {
        let measurements = try await measurementSystem.calculateMeasurements(
            from: area.meshData,
            regions: [.init(type: .custom("Selected Area", "cm²"), boundaries: area.points)]
        )
        
        return AreaMetrics(
            id: area.id,
            area: measurements.customMeasurements.first?.value ?? 0,
            density: try await graftCalculator.densityAnalyzer.analyzeExistingDensity(
                area: measurements.customMeasurements.first?.value ?? 0,
                preferences: .default
            )
        )
    }
}

private struct SelectedArea {
    let id: UUID
    let initialPosition: SIMD3<Float>
    let brushSize: Float
    var points: [SIMD3<Float>]
    var color: CGColor?
    var meshData: MeshData {
        // Convert points to mesh data format
        MeshData(vertices: points)
    }
}

public struct AreaMetrics {
    public let id: UUID
    public let area: Float
    public let density: Float
    public var estimatedGrafts: Int {
        Int(area * density)
    }
}

public extension Notification.Name {
    static let areaMetricsUpdated = Notification.Name("areaMetricsUpdated")
    static let areaColorChanged = Notification.Name("areaColorChanged")
    static let graftCalculationsUpdated = Notification.Name("graftCalculationsUpdated")
}