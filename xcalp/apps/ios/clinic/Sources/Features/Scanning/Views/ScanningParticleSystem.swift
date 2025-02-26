import SwiftUI

struct ScanningParticleSystem: View {
    let quality: Float
    let coverage: Float
    let isScanning: Bool
    
    @State private var particles: [Particle] = []
    @State private var lastUpdate = Date()
    private let timer = Timer.publish(
        every: 0.016,  // ~60fps
        on: .main,
        in: .common
    ).autoconnect()
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    var contextCopy = context
                    let xPos = particle.x * size.width
                    let yPos = particle.y * size.height
                    
                    contextCopy.opacity = particle.opacity
                    contextCopy.blendMode = .plusLighter
                    
                    // Draw particle with dynamic color
                    let rect = CGRect(
                        x: xPos,
                        y: yPos,
                        width: particle.size,
                        height: particle.size
                    )
                    
                    let path = Circle().path(in: rect)
                    contextCopy.addFilter(.blur(radius: particle.size * 0.5))
                    contextCopy.fill(path, with: .color(particle.color))
                }
            }
        }
        .onChange(of: isScanning) { scanning in
            if scanning {
                particles = []
                spawnInitialParticles()
            }
        }
        .onReceive(timer) { currentTime in
            guard isScanning else { return }
            
            let delta = currentTime.timeIntervalSince(lastUpdate)
            updateParticles(deltaTime: delta)
            lastUpdate = currentTime
            
            if quality > 0.5 {
                spawnNewParticles()
            }
        }
    }
    
    private func spawnInitialParticles() {
        for _ in 0..<50 {
            particles.append(Particle.random(quality: quality))
        }
    }
    
    private func spawnNewParticles() {
        let spawnCount = Int(quality * 5)
        for _ in 0..<spawnCount {
            if particles.count < 200 {
                particles.append(Particle.random(quality: quality))
            }
        }
    }
    
    private func updateParticles(deltaTime: TimeInterval) {
        particles = particles.compactMap { particle in
            var updatedParticle = particle
            
            // Update position
            updatedParticle.x += particle.velocityX * Float(deltaTime)
            updatedParticle.y += particle.velocityY * Float(deltaTime)
            
            // Update lifetime and opacity
            updatedParticle.lifetime -= Float(deltaTime)
            updatedParticle.opacity = particle.lifetime / particle.initialLifetime
            
            // Apply quality-based effects
            updatedParticle.size += Float(deltaTime) * quality * 2
            
            // Remove dead particles
            guard updatedParticle.lifetime > 0 else { return nil }
            return updatedParticle
        }
    }
}

struct Particle {
    var x: Float
    var y: Float
    var velocityX: Float
    var velocityY: Float
    var size: Float
    var color: Color
    var opacity: Float
    var lifetime: Float
    var initialLifetime: Float
    
    static func random(quality: Float) -> Particle {
        let lifetime = Float.random(in: 0.5...2.0)
        let color = Self.colorForQuality(quality)
        
        return Particle(
            x: Float.random(in: 0...1),
            y: Float.random(in: 0...1),
            velocityX: Float.random(in: -0.2...0.2),
            velocityY: Float.random(in: -0.2...0.2),
            size: Float.random(in: 2...8),
            color: color,
            opacity: 1.0,
            lifetime: lifetime,
            initialLifetime: lifetime
        )
    }
    
    private static func colorForQuality(_ quality: Float) -> Color {
        switch quality {
        case 0..<0.3:
            return .red
        case 0.3..<0.7:
            return .orange
        default:
            return .green
        }
    }
}