import AVFoundation
import AudioToolbox

public class ScannerSoundSynthesizer {
    private var audioEngine: AVAudioEngine
    private var mainMixer: AVAudioMixerNode
    private var beepGenerator: AVAudioSourceNode
    private var pulseGenerator: AVAudioSourceNode
    
    private var baseFrequency: Float = 880.0 // A5 note
    private var pulseRate: Float = 1.0
    private var currentAmplitude: Float = 0.0
    private let sampleRate: Double = 44100.0
    private var phase: Float = 0.0
    private var pulsePhase: Float = 0.0
    
    private var isActive = false
    private var qualityModulation: Float = 1.0
    
    public init() {
        audioEngine = AVAudioEngine()
        mainMixer = audioEngine.mainMixerNode
        
        // Create beep tone generator
        beepGenerator = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            for frame in 0..<Int(frameCount) {
                // Generate main beep tone
                let beepValue = sin(2.0 * Float.pi * self.phase)
                self.phase += self.baseFrequency / Float(self.sampleRate)
                if self.phase >= 1.0 { self.phase -= 1.0 }
                
                // Apply pulse modulation
                let pulseValue = sin(2.0 * Float.pi * self.pulsePhase)
                self.pulsePhase += self.pulseRate / Float(self.sampleRate)
                if self.pulsePhase >= 1.0 { self.pulsePhase -= 1.0 }
                
                // Combine signals
                let envelopedValue = beepValue * max(0, pulseValue)
                ptr?[frame] = envelopedValue * self.currentAmplitude * self.qualityModulation
            }
            
            return noErr
        }
        
        // Create rhythmic pulse generator
        pulseGenerator = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
            
            for frame in 0..<Int(frameCount) {
                // Generate rhythmic pulse
                let pulseFreq: Float = 4.0 // 4 Hz pulse
                let pulseValue = sin(2.0 * Float.pi * self.pulsePhase)
                self.pulsePhase += pulseFreq / Float(self.sampleRate)
                if self.pulsePhase >= 1.0 { self.pulsePhase -= 1.0 }
                
                // Apply envelope
                ptr?[frame] = max(0, pulseValue) * 0.2 * self.currentAmplitude
            }
            
            return noErr
        }
        
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // Configure audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        
        // Setup audio processing chain
        audioEngine.attach(beepGenerator)
        audioEngine.attach(pulseGenerator)
        
        // Connect nodes with appropriate formats
        let format = AVAudioFormat(
            commonFormat: .pcmFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        
        audioEngine.connect(beepGenerator, to: mainMixer, format: format)
        audioEngine.connect(pulseGenerator, to: mainMixer, format: format)
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    public func updateQuality(_ quality: Float) {
        // Adjust frequency based on quality
        let normalizedQuality = max(0.3, min(quality, 1.0))
        baseFrequency = 880.0 + (normalizedQuality - 0.5) * 440.0
        
        // Adjust pulse rate based on quality
        pulseRate = 1.0 + normalizedQuality * 2.0
        
        // Adjust modulation
        qualityModulation = normalizedQuality
    }
    
    public func updateSpeed(_ speed: Float) {
        // Adjust pulse rate based on speed
        let normalizedSpeed = min(speed, 2.0)
        pulseRate = normalizedSpeed * 2.0
    }
    
    public func start() {
        guard !isActive else { return }
        isActive = true
        
        // Fade in amplitude
        currentAmplitude = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.currentAmplitude < 0.3 {
                self.currentAmplitude += 0.01
            } else {
                timer.invalidate()
            }
        }
    }
    
    public func stop() {
        isActive = false
        
        // Fade out amplitude
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.currentAmplitude > 0.0 {
                self.currentAmplitude -= 0.01
            } else {
                timer.invalidate()
            }
        }
    }
    
    deinit {
        audioEngine.stop()
    }
}