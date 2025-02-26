import AVFoundation
import CoreLocation
import Accelerate
import SwiftUI

public class AudioGuideController {
    private let synthesizer = AVSpeechSynthesizer()
    private var beaconAudioEngine: AVAudioEngine?
    private var beaconPlayer: AVAudioPlayerNode?
    private var lastGuidanceTime: TimeInterval = 0
    private var isGuiding = false
    private var currentGuidanceArea: ScanningArea?
    private let hapticEngine = HapticFeedback.shared
    private let guidanceInterval: TimeInterval = 2.0
    
    private enum ScanningArea: String {
        case top = "upper area"
        case bottom = "lower area"
        case left = "left side"
        case right = "right side"
        case center = "center"
        case tooClose = "too close"
        case tooFar = "too far"
    }
    
    private struct GuidanceBeacon {
        let frequency: Float
        let duration: TimeInterval
        let intensity: Float
        let direction: ScanningArea
    }
    
    public init() {
        setupAudioSession()
        setupBeaconAudio()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func setupBeaconAudio() {
        beaconAudioEngine = AVAudioEngine()
        beaconPlayer = AVAudioPlayerNode()
        
        guard let engine = beaconAudioEngine,
              let player = beaconPlayer else { return }
        
        engine.attach(player)
        engine.connect(
            player,
            to: engine.mainMixerNode,
            format: nil
        )
        
        do {
            try engine.start()
        } catch {
            print("Failed to start beacon audio engine: \(error)")
        }
    }
    
    public func startGuidance() {
        isGuiding = true
        speakGuidance("Starting guided scanning. Move your device slowly and listen for audio cues.")
    }
    
    public func stopGuidance() {
        isGuiding = false
        synthesizer.stopSpeaking(at: .immediate)
        beaconAudioEngine?.stop()
    }
    
    public func updateGuidance(
        devicePosition: simd_float3,
        targetPosition: simd_float3,
        quality: Float,
        coverage: Float
    ) {
        guard isGuiding else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastGuidanceTime >= guidanceInterval else {
            return
        }
        
        // Determine scanning area that needs attention
        let area = determineScanningArea(
            devicePosition: devicePosition,
            targetPosition: targetPosition
        )
        
        if area != currentGuidanceArea {
            currentGuidanceArea = area
            provideAreaGuidance(area)
        }
        
        // Generate appropriate beacon
        if let beacon = generateBeacon(
            for: area,
            quality: quality,
            coverage: coverage
        ) {
            playBeacon(beacon)
        }
        
        // Provide quality feedback
        if quality < 0.3 {
            speakGuidance("Quality too low. Move more slowly.")
            hapticEngine.playErrorFeedback()
        } else if quality > 0.8 && coverage > 0.8 {
            speakGuidance("Excellent scan quality and coverage.")
            hapticEngine.playSuccessFeedback()
        }
        
        lastGuidanceTime = currentTime
    }
    
    private func determineScanningArea(
        devicePosition: simd_float3,
        targetPosition: simd_float3
    ) -> ScanningArea {
        let distance = length(devicePosition - targetPosition)
        
        if distance < 0.3 {
            return .tooClose
        } else if distance > 2.0 {
            return .tooFar
        }
        
        let direction = normalize(devicePosition - targetPosition)
        
        if abs(direction.y) > 0.7 {
            return direction.y > 0 ? .top : .bottom
        } else if abs(direction.x) > 0.7 {
            return direction.x > 0 ? .right : .left
        }
        
        return .center
    }
    
    private func generateBeacon(
        for area: ScanningArea,
        quality: Float,
        coverage: Float
    ) -> GuidanceBeacon? {
        let baseFrequency: Float
        let intensity = quality
        
        switch area {
        case .top:
            baseFrequency = 880.0 // A5
        case .bottom:
            baseFrequency = 440.0 // A4
        case .left:
            baseFrequency = 587.33 // D5
        case .right:
            baseFrequency = 659.25 // E5
        case .center:
            baseFrequency = 523.25 // C5
        case .tooClose:
            baseFrequency = 987.77 // B5
        case .tooFar:
            baseFrequency = 329.63 // E4
        }
        
        return GuidanceBeacon(
            frequency: baseFrequency,
            duration: 0.2,
            intensity: intensity,
            direction: area
        )
    }
    
    private func playBeacon(_ beacon: GuidanceBeacon) {
        guard let engine = beaconAudioEngine,
              let player = beaconPlayer else { return }
        
        // Generate beacon tone
        let sampleRate: Double = 44100.0
        let numSamples = Int(sampleRate * beacon.duration)
        var audioData = [Float](repeating: 0.0, capacity: numSamples)
        
        // Generate sine wave
        for i in 0..<numSamples {
            let phase = Float(i) * 2.0 * Float.pi * beacon.frequency / Float(sampleRate)
            audioData[i] = sin(phase) * beacon.intensity
        }
        
        // Apply envelope
        let attackSamples = Int(0.01 * sampleRate)
        let releaseSamples = Int(0.01 * sampleRate)
        
        for i in 0..<attackSamples {
            let envelope = Float(i) / Float(attackSamples)
            audioData[i] *= envelope
        }
        
        for i in (numSamples - releaseSamples)..<numSamples {
            let envelope = Float(numSamples - i) / Float(releaseSamples)
            audioData[i] *= envelope
        }
        
        // Create audio buffer
        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        
        let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat!,
            frameCapacity: AVAudioFrameCount(numSamples)
        )
        
        buffer?.frameLength = AVAudioFrameCount(numSamples)
        memcpy(buffer?.floatChannelData?[0], &audioData, numSamples * 4)
        
        player.scheduleBuffer(buffer!, at: nil, options: .interrupts)
        player.play()
    }
    
    private func speakGuidance(_ message: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
    
    private func generateDirectionalBeacon(
        angle: Float,
        distance: Float,
        intensity: Float
    ) -> Data {
        let sampleRate: Float = 44100.0
        let duration: Float = 0.2
        let numSamples = Int(sampleRate * duration)
        var audioData = [Float](repeating: 0.0, count: numSamples)
        
        // Base frequency varies with distance
        let baseFrequency = 440.0 + (1.0 - min(distance, 2.0) / 2.0) * 440.0
        
        // Modulation frequency varies with angle
        let modulationFrequency = 2.0 + abs(angle) * 4.0
        
        for i in 0..<numSamples {
            let t = Float(i) / sampleRate
            let carrier = sin(2.0 * .pi * baseFrequency * t)
            let modulator = sin(2.0 * .pi * modulationFrequency * t)
            audioData[i] = carrier * modulator * intensity
        }
        
        return Data(bytes: &audioData, count: numSamples * 4)
    }
    
    deinit {
        stopGuidance()
        beaconAudioEngine?.stop()
    }
}