import AVFoundation
import CoreHaptics
import CoreMotion

public class DynamicAudioController {
    private var engine: AVAudioEngine
    private var spatialMixer: AVAudioMixerNode
    private var oscillator: AVAudioSourceNode
    private var noiseGenerator: AVAudioSourceNode
    private var speedModulator: AVAudioUnitTimePitch
    
    private var baseFrequency: Float = 440.0
    private var currentAmplitude: Float = 0.1
    private let sampleRate: Double = 44100.0
    private var phase: Float = 0.0
    
    private var isActive = false
    private var lastPosition: SIMD3<Float>?
    private let motionManager = CMMotionManager()
    
    private let scannerSynth = ScannerSoundSynthesizer()
    private var isScannerSoundEnabled = true
    
    public init() {
        engine = AVAudioEngine()
        spatialMixer = AVAudioMixerNode()
        speedModulator = AVAudioUnitTimePitch()
        
        // Create oscillator for tonal feedback
        oscillator = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            for frame in 0..<Int(frameCount) {
                let sineValue = sin(2.0 * Float.pi * self.phase)
                self.phase += self.baseFrequency / Float(self.sampleRate)
                if self.phase >= 1.0 { self.phase -= 1.0 }
                
                ptr?[frame] = sineValue * self.currentAmplitude
            }
            return noErr
        }
        
        // Create noise generator for movement feedback
        noiseGenerator = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            for frame in 0..<Int(frameCount) {
                ptr?[frame] = (Float.random(in: -1...1)) * self.currentAmplitude
            }
            return noErr
        }
        
        setupAudioEngine()
        setupMotionTracking()
    }
    
    private func setupAudioEngine() {
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        
        // Setup audio processing chain
        engine.attach(oscillator)
        engine.attach(noiseGenerator)
        engine.attach(spatialMixer)
        
        // Connect nodes
        engine.connect(oscillator, to: spatialMixer, format: nil)
        engine.connect(noiseGenerator, to: spatialMixer, format: nil)
        engine.connect(spatialMixer, to: engine.mainMixerNode, format: nil)
        
        // Configure spatial mixer
        spatialMixer.renderingAlgorithm = .HRTF
        spatialMixer.reverbBlend = 0.3
        
        // Start engine
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates()
    }
    
    public func updateAudioFeedback(
        position: SIMD3<Float>,
        speed: Float,
        quality: Float
    ) {
        guard isActive else { return }
        
        // Update spatial position
        let rotation = motionManager.deviceMotion?.attitude.rotationMatrix
        let transformedPosition = transformPosition(position, rotation: rotation)
        updateSpatialPosition(transformedPosition)
        
        // Update audio characteristics based on scanning parameters
        updateTonalFeedback(quality: quality)
        updateMovementFeedback(speed: speed)
        
        // Update scanner synth parameters
        if isScannerSoundEnabled {
            scannerSynth.updateQuality(quality)
            scannerSynth.updateSpeed(speed)
        }
        
        lastPosition = position
    }
    
    private func transformPosition(
        _ position: SIMD3<Float>,
        rotation: CMRotationMatrix?
    ) -> SIMD3<Float> {
        guard let rotation = rotation else { return position }
        
        let rotationMatrix = simd_float3x3(
            SIMD3<Float>(Float(rotation.m11), Float(rotation.m12), Float(rotation.m13)),
            SIMD3<Float>(Float(rotation.m21), Float(rotation.m22), Float(rotation.m23)),
            SIMD3<Float>(Float(rotation.m31), Float(rotation.m32), Float(rotation.m33))
        )
        
        return rotationMatrix * position
    }
    
    private func updateSpatialPosition(_ position: SIMD3<Float>) {
        // Convert position to audio space coordinates
        spatialMixer.position = AVAudio3DPoint(
            x: position.x,
            y: position.y,
            z: position.z
        )
    }
    
    private func updateTonalFeedback(quality: Float) {
        // Modify frequency based on quality
        let normalizedQuality = max(0.3, min(quality, 1.0))
        baseFrequency = 440.0 + (normalizedQuality - 0.5) * 200.0
        
        // Adjust amplitude based on quality
        currentAmplitude = 0.1 + (1.0 - normalizedQuality) * 0.2
    }
    
    private func updateMovementFeedback(speed: Float) {
        // Modulate noise based on movement speed
        let normalizedSpeed = min(speed, 2.0) / 2.0
        speedModulator.rate = Float(1.0 + normalizedSpeed)
        
        // Adjust noise amplitude based on speed
        if speed > 1.2 {
            currentAmplitude = 0.2
        } else {
            currentAmplitude = 0.1
        }
    }
    
    public func startAudioFeedback() {
        isActive = true
        currentAmplitude = 0.1
        if isScannerSoundEnabled {
            scannerSynth.start()
        }
    }
    
    public func stopAudioFeedback() {
        isActive = false
        currentAmplitude = 0.0
        scannerSynth.stop()
    }
    
    public func setScannerSoundEnabled(_ enabled: Bool) {
        isScannerSoundEnabled = enabled
        if !enabled {
            scannerSynth.stop()
        } else if isActive {
            scannerSynth.start()
        }
    }
    
    deinit {
        engine.stop()
        motionManager.stopDeviceMotionUpdates()
    }
}