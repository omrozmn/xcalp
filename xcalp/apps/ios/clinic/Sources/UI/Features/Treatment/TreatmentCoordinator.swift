import Foundation
import Combine
import CoreGraphics

extension GraftPreferences {
    static let `default` = GraftPreferences(
        targetDensity: 45.0,
        maxDonorDensity: 35.0,
        typeDistribution: [
            .single: 0.3,
            .double: 0.4,
            .triple: 0.2,
            .quadruple: 0.1
        ],
        graftTypePriorities: [.double, .triple, .single, .quadruple],
        zonePreferences: []
    )
}

public final class TreatmentCoordinator {
    private let meshTools: InteractiveMeshTools
    private let graftCalculator: GraftCalculator
    private let documentGenerator: DocumentGenerator
    private var subscribers: Set<AnyCancellable> = []
    private var activeAreas: [UUID: AreaMetrics] = [:]
    
    public init(
        meshTools: InteractiveMeshTools = InteractiveMeshTools(),
        graftCalculator: GraftCalculator = GraftCalculator(),
        documentGenerator: DocumentGenerator = DocumentGenerator()
    ) {
        self.meshTools = meshTools
        self.graftCalculator = graftCalculator
        self.documentGenerator = documentGenerator
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Listen for area updates
        NotificationCenter.default.publisher(for: .areaMetricsUpdated)
            .sink { [weak self] notification in
                guard let metrics = notification.userInfo?["metrics"] as? AreaMetrics else { return }
                self?.handleAreaUpdate(metrics)
            }
            .store(in: &subscribers)
            
        // Listen for color changes
        NotificationCenter.default.publisher(for: .areaColorChanged)
            .sink { [weak self] notification in
                guard let id = notification.userInfo?["id"] as? UUID,
                      let color = notification.userInfo?["color"] as? CGColor else { return }
                self?.handleColorUpdate(id: id, color: color)
            }
            .store(in: &subscribers)
    }
    
    private func handleAreaUpdate(_ metrics: AreaMetrics) {
        activeAreas[metrics.id] = metrics
        updateTotalCalculations()
    }
    
    private func handleColorUpdate(id: UUID, color: CGColor) {
        // Update visualization if needed
        NotificationCenter.default.post(
            name: .visualizationUpdate,
            object: nil,
            userInfo: ["id": id, "color": color]
        )
    }
    
    private func updateTotalCalculations() {
        let totalArea = activeAreas.values.reduce(0) { $0 + $1.area }
        let totalGrafts = activeAreas.values.reduce(0) { $0 + $1.estimatedGrafts }
        
        NotificationCenter.default.post(
            name: .totalMetricsUpdated,
            object: nil,
            userInfo: [
                "totalArea": totalArea,
                "totalGrafts": totalGrafts
            ]
        )
    }
    
    public func generateReport(patientInfo: PatientInfo) async throws -> Data {
        // Gather all measurements
        let measurements = Measurements(
            totalArea: activeAreas.values.reduce(0) { $0 + $1.area },
            recipientArea: activeAreas.values.filter { $0.density > 0 }.reduce(0) { $0 + $1.area },
            donorArea: activeAreas.values.filter { $0.density == 0 }.reduce(0) { $0 + $1.area },
            scalpThickness: 0, // This should come from actual measurements
            customMeasurements: []
        )
        
        // Calculate grafts
        let graftCalculation = try await graftCalculator.calculateGrafts(
            measurements: measurements,
            preferences: .default
        )
        
        // Generate document
        return try documentGenerator.generateTreatmentPlan(
            measurements: measurements,
            graftCalculation: graftCalculation,
            patientInfo: patientInfo
        )
    }
}

public extension Notification.Name {
    static let visualizationUpdate = Notification.Name("visualizationUpdate")
    static let totalMetricsUpdated = Notification.Name("totalMetricsUpdated")
}