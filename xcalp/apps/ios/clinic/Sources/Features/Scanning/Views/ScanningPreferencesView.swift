import SwiftUI

struct ScanningPreferencesView: View {
    @Binding var preferences: ScanningPreferences
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Audio Settings
                Section(header: Text("Audio Feedback")) {
                    Toggle("Scanner Sound", isOn: $preferences.isScannerSoundEnabled)
                    if preferences.isScannerSoundEnabled {
                        VolumeSlider(
                            value: $preferences.scannerSoundVolume,
                            label: "Scanner Volume"
                        )
                    }
                    
                    Toggle("Spatial Audio", isOn: $preferences.isSpatialAudioEnabled)
                    if preferences.isSpatialAudioEnabled {
                        VolumeSlider(
                            value: $preferences.spatialAudioVolume,
                            label: "Spatial Audio Volume"
                        )
                    }
                    
                    Toggle("Voice Guidance", isOn: $preferences.isVoiceFeedbackEnabled)
                    if preferences.isVoiceFeedbackEnabled {
                        VolumeSlider(
                            value: $preferences.voiceFeedbackVolume,
                            label: "Voice Volume"
                        )
                    }
                }
                
                // Haptic Settings
                Section(header: Text("Haptic Feedback")) {
                    Toggle("Enable Haptics", isOn: $preferences.isHapticFeedbackEnabled)
                    if preferences.isHapticFeedbackEnabled {
                        IntensitySlider(
                            value: $preferences.hapticIntensity,
                            label: "Haptic Intensity"
                        )
                    }
                }
                
                // Visual Settings
                Section(header: Text("Visual Guidance")) {
                    Toggle("Visual Guide", isOn: $preferences.isVisualGuideEnabled)
                    if preferences.isVisualGuideEnabled {
                        Toggle("Speed Gauge", isOn: $preferences.showSpeedGauge)
                        Toggle("Quality Metrics", isOn: $preferences.showQualityMetrics)
                        Toggle("Coverage Map", isOn: $preferences.showCoverageMap)
                    }
                }
                
                // Quality Settings
                Section(header: Text("Scanning Thresholds")) {
                    ThresholdSlider(
                        value: $preferences.minimumQualityThreshold,
                        label: "Minimum Quality",
                        description: "Required quality before capture"
                    )
                    
                    ThresholdSlider(
                        value: $preferences.minimumCoverageThreshold,
                        label: "Minimum Coverage",
                        description: "Required area coverage"
                    )
                }
                
                // Guidance Settings
                Section(header: Text("Guidance Settings")) {
                    Stepper(
                        value: $preferences.guidanceUpdateInterval,
                        in: 1...5,
                        step: 0.5
                    ) {
                        VStack(alignment: .leading) {
                            Text("Guidance Interval")
                            Text("\(preferences.guidanceUpdateInterval, specifier: "%.1f") seconds")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Scanning Preferences")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        preferences.savePreferences()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct VolumeSlider: View {
    @Binding var value: Float
    let label: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ))
                Image(systemName: "speaker.wave.3.fill")
            }
        }
    }
}

private struct IntensitySlider: View {
    @Binding var value: Float
    let label: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                Slider(value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ))
                Image(systemName: "dot.radiowaves.forward")
            }
        }
    }
}

private struct ThresholdSlider: View {
    @Binding var value: Float
    let label: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text("0%")
                Slider(value: Binding(
                    get: { Double(value) },
                    set: { value = Float($0) }
                ))
                Text("100%")
            }
            Text("\(Int(value * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#if DEBUG
struct ScanningPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        ScanningPreferencesView(
            preferences: .constant(ScanningPreferences())
        )
    }
}