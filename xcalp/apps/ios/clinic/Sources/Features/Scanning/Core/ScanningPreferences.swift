import Foundation

public struct ScanningPreferences {
    public var isScannerSoundEnabled: Bool = true
    public var isHapticFeedbackEnabled: Bool = true
    public var isSpatialAudioEnabled: Bool = true
    public var isVoiceFeedbackEnabled: Bool = true
    public var isVisualGuideEnabled: Bool = true
    
    // Audio settings
    public var scannerSoundVolume: Float = 0.7
    public var voiceFeedbackVolume: Float = 1.0
    public var spatialAudioVolume: Float = 0.8
    
    // Haptic settings
    public var hapticIntensity: Float = 1.0
    
    // Visual settings
    public var showSpeedGauge: Bool = true
    public var showQualityMetrics: Bool = true
    public var showCoverageMap: Bool = true
    
    // Guidance settings
    public var minimumQualityThreshold: Float = 0.7
    public var minimumCoverageThreshold: Float = 0.8
    public var guidanceUpdateInterval: TimeInterval = 2.0
    
    // Persistence
    private let defaults = UserDefaults.standard
    private let prefixKey = "com.xcalp.scanning.preferences"
    
    public init() {
        loadPreferences()
    }
    
    public mutating func loadPreferences() {
        isScannerSoundEnabled = defaults.bool(forKey: key("scannerSound")) 
        isHapticFeedbackEnabled = defaults.bool(forKey: key("hapticFeedback"))
        isSpatialAudioEnabled = defaults.bool(forKey: key("spatialAudio"))
        isVoiceFeedbackEnabled = defaults.bool(forKey: key("voiceFeedback"))
        isVisualGuideEnabled = defaults.bool(forKey: key("visualGuide"))
        
        scannerSoundVolume = defaults.float(forKey: key("scannerVolume"))
        voiceFeedbackVolume = defaults.float(forKey: key("voiceVolume"))
        spatialAudioVolume = defaults.float(forKey: key("spatialVolume"))
        
        hapticIntensity = defaults.float(forKey: key("hapticIntensity"))
        
        showSpeedGauge = defaults.bool(forKey: key("speedGauge"))
        showQualityMetrics = defaults.bool(forKey: key("qualityMetrics"))
        showCoverageMap = defaults.bool(forKey: key("coverageMap"))
        
        minimumQualityThreshold = defaults.float(forKey: key("qualityThreshold"))
        minimumCoverageThreshold = defaults.float(forKey: key("coverageThreshold"))
        guidanceUpdateInterval = defaults.double(forKey: key("guidanceInterval"))
    }
    
    public func savePreferences() {
        defaults.set(isScannerSoundEnabled, forKey: key("scannerSound"))
        defaults.set(isHapticFeedbackEnabled, forKey: key("hapticFeedback"))
        defaults.set(isSpatialAudioEnabled, forKey: key("spatialAudio"))
        defaults.set(isVoiceFeedbackEnabled, forKey: key("voiceFeedback"))
        defaults.set(isVisualGuideEnabled, forKey: key("visualGuide"))
        
        defaults.set(scannerSoundVolume, forKey: key("scannerVolume"))
        defaults.set(voiceFeedbackVolume, forKey: key("voiceVolume"))
        defaults.set(spatialAudioVolume, forKey: key("spatialVolume"))
        
        defaults.set(hapticIntensity, forKey: key("hapticIntensity"))
        
        defaults.set(showSpeedGauge, forKey: key("speedGauge"))
        defaults.set(showQualityMetrics, forKey: key("qualityMetrics"))
        defaults.set(showCoverageMap, forKey: key("coverageMap"))
        
        defaults.set(minimumQualityThreshold, forKey: key("qualityThreshold"))
        defaults.set(minimumCoverageThreshold, forKey: key("coverageThreshold"))
        defaults.set(guidanceUpdateInterval, forKey: key("guidanceInterval"))
    }
    
    private func key(_ name: String) -> String {
        return "\(prefixKey).\(name)"
    }
}