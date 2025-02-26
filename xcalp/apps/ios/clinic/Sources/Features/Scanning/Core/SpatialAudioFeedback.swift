import AVFoundation
import SceneKit

public class SpatialAudioFeedback {
    private var audioEngine: AVAudioEngine
    private var audioEnvironment: AVAudioEnvironment
    private var audioPlayerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    
    private let audioQueue = DispatchQueue(label: "com.xcalp.spatialaudio")
    private var isEnabled = true
    private let dynamicAudio = DynamicAudioController()
    private var lastQualityUpdate: TimeInterval = 0
    private let qualityUpdateInterval: TimeInterval = 0.5
    
    public init() {
        audioEngine = AVAudioEngine()
        audioEnvironment = audioEngine.mainMixerNode.environmentNode
        setupAudioSession()
        loadAudioResources()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spatialAudio,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func loadAudioResources() {
        let sounds = [
            "coverage_low": "coverage_notification.wav",
            "quality_alert": "quality_alert.wav",
            "scanning_complete": "scan_complete.wav",
            "movement_guide": "movement_guide.wav"
        ]
        
        for (key, filename) in sounds {
            if let url = Bundle.module.url(forResource: filename, withExtension: nil) {
                do {
                    let file = try AVAudioFile(forReading: url)
                    audioFiles[key] = file
                    let player = AVAudioPlayerNode()
                    audioPlayerNodes[key] = player
                    audioEngine.attach(player)
                    audioEngine.connect(
                        player,
                        to: audioEngine.mainMixerNode,
                        format: file.processingFormat
                    )
                } catch {
                    print("Failed to load audio file \(filename): \(error)")
                }
            }
        }
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    public func playSpatialSound(
        _ sound: String,
        at position: SIMD3<Float>,
        volume: Float = 1.0
    ) {
        guard isEnabled,
              let player = audioPlayerNodes[sound],
              let file = audioFiles[sound] else {
            return
        }
        
        audioQueue.async {
            // Convert position to audio space
            let audioPosition = AVAudio3DPoint(
                x: position.x,
                y: position.y,
                z: position.z
            )
            player.position = audioPosition
            
            // Set volume and other properties
            player.renderingAlgorithm = .HRTF
            player.reverbBlend = 0.5
            player.volume = volume
            
            // Schedule and play the sound
            do {
                try player.scheduledFile(
                    file,
                    at: nil,
                    completionHandler: nil
                )
                player.play()
            } catch {
                print("Failed to play spatial sound: \(error)")
            }
        }
    }
    
    public func playDirectionalCue(
        direction: ScanDirection,
        intensity: Float
    ) {
        let position: SIMD3<Float>
        
        switch direction {
        case .left:
            position = SIMD3<Float>(-1, 0, 0)
        case .right:
            position = SIMD3<Float>(1, 0, 0)
        case .up:
            position = SIMD3<Float>(0, 1, 0)
        case .down:
            position = SIMD3<Float>(0, -1, 0)
        case .forward:
            position = SIMD3<Float>(0, 0, -1)
        case .backward:
            position = SIMD3<Float>(0, 0, 1)
        }
        
        playSpatialSound(
            "movement_guide",
            at: position,
            volume: intensity
        )
    }
    
    public func playCoverageAlert(
        missingArea: SIMD3<Float>,
        urgency: Float
    ) {
        playSpatialSound(
            "coverage_low",
            at: missingArea,
            volume: urgency
        )
    }
    
    public func playQualityAlert(severity: Float) {
        playSpatialSound(
            "quality_alert",
            at: SIMD3<Float>(0, 0, -1),
            volume: severity
        )
    }
    
    public func playCompletionSound() {
        playSpatialSound(
            "scanning_complete",
            at: SIMD3<Float>(0, 0, 0),
            volume: 1.0
        )
    }
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            audioQueue.async {
                self.audioPlayerNodes.values.forEach { $0.stop() }
            }
        }
    }
    
    public enum ScanDirection {
        case left
        case right
        case up
        case down
        case forward
        case backward
    }
    
    public func updateScanningFeedback(
        position: SIMD3<Float>,
        speed: Float,
        quality: Float
    ) {
        let currentTime = CACurrentMediaTime()
        
        // Update dynamic audio feedback
        dynamicAudio.updateAudioFeedback(
            position: position,
            speed: speed,
            quality: quality
        )
        
        // Provide discrete audio cues for significant changes
        if currentTime - lastQualityUpdate >= qualityUpdateInterval {
            if quality < 0.3 {
                playQualityAlert(severity: 1.0 - quality)
            } else if quality > 0.8 {
                playSpatialSound(
                    "quality_alert",
                    at: position,
                    volume: 0.3
                )
            }
            lastQualityUpdate = currentTime
        }
    }
    
    public func startContinuousFeedback() {
        dynamicAudio.startAudioFeedback()
    }
    
    public func stopContinuousFeedback() {
        dynamicAudio.stopAudioFeedback()
    }
    
    deinit {
        audioEngine.stop()
    }
}