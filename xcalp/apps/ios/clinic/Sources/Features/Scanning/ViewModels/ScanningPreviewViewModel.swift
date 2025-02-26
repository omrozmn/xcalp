import SwiftUI
import Combine

public class ScanningPreviewViewModel: ObservableObject {
    @Published var scanningQuality: Float = 0
    @Published var coverage: Float = 0
    @Published var currentSpeed: Float = 0
    @Published var optimizedSpeed: Float = 0.5
    @Published var speedGuidance: String = ""
    @Published var guidanceMessage: String = ""
    @Published var hints: [OptimizationHint] = []
    @Published var isShowingPreferences = false
    @Published var preferences: ScanningPreferences
    @Published var metrics: ScanningMetrics?
    @Published var showingGuide: Bool = true
    
    private var scanningFeature: ScanningFeature
    private var cancellables = Set<AnyCancellable>()
    
    public init(scanningFeature: ScanningFeature) {
        self.scanningFeature = scanningFeature
        self.preferences = ScanningPreferences()
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Bind scanning quality updates
        scanningFeature.$scanningQuality
            .receive(on: DispatchQueue.main)
            .assign(to: \.scanningQuality, on: self)
            .store(in: &cancellables)
        
        // Bind coverage updates
        scanningFeature.$scanCoverage
            .receive(on: DispatchQueue.main)
            .assign(to: \.coverage, on: self)
            .store(in: &cancellables)
        
        // Bind speed updates
        scanningFeature.$currentSpeed
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentSpeed, on: self)
            .store(in: &cancellables)
        
        // Bind guidance updates
        scanningFeature.$guidanceMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.guidanceMessage, on: self)
            .store(in: &cancellables)
        
        // Bind optimization hints
        scanningFeature.$currentHints
            .receive(on: DispatchQueue.main)
            .assign(to: \.hints, on: self)
            .store(in: &cancellables)
        
        // Bind performance metrics
        scanningFeature.$currentMetrics
            .receive(on: DispatchQueue.main)
            .assign(to: \.metrics, on: self)
            .store(in: &cancellables)
    }
    
    func toggleFeature(_ feature: ScanningFeature.ScanningFeature) {
        scanningFeature.toggleFeature(feature)
    }
    
    func updatePreferences() {
        scanningFeature.updatePreferences(preferences)
    }
    
    func toggleGuide() {
        showingGuide.toggle()
        scanningFeature.toggleScanningGuide()
    }
    
    var shouldShowSpeedGauge: Bool {
        preferences.showSpeedGauge && showingGuide
    }
    
    var shouldShowMetrics: Bool {
        preferences.showQualityMetrics
    }
    
    var shouldShowCoverageMap: Bool {
        preferences.showCoverageMap && showingGuide
    }
    
    var isQualityAcceptable: Bool {
        scanningQuality >= preferences.minimumQualityThreshold
    }
    
    var isCoverageAcceptable: Bool {
        coverage >= preferences.minimumCoverageThreshold
    }
    
    var canCapture: Bool {
        isQualityAcceptable && isCoverageAcceptable
    }
}