import SwiftUI
import SceneKit

struct CoverageHeatmapView: View {
    let heatmap: [(position: SIMD3<Float>, density: Float)]
    let coverage: Float
    
    var body: some View {
        VStack(spacing: 16) {
            // 3D heatmap visualization
            SceneView(
                scene: createHeatmapScene(),
                options: [.allowsCameraControl]
            )
            .frame(height: 200)
            
            // Coverage legend
            VStack(spacing: 8) {
                Text("Coverage Map")
                    .font(.headline)
                
                HStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .red,
                            .orange,
                            .yellow,
                            .green
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 8)
                    .cornerRadius(4)
                    
                    Text("\(Int(coverage * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Low")
                    Spacer()
                    Text("High")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
    
    private func createHeatmapScene() -> SCNScene {
        let scene = SCNScene()
        
        // Create ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 100
        scene.rootNode.addChildNode(ambientLight)
        
        // Create camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2)
        scene.rootNode.addChildNode(cameraNode)
        
        // Add heatmap points
        for point in heatmap {
            let sphere = SCNSphere(radius: 0.01)
            let node = SCNNode(geometry: sphere)
            
            // Position
            node.position = SCNVector3(
                point.position.x,
                point.position.y,
                point.position.z
            )
            
            // Color based on density
            node.geometry?.firstMaterial?.diffuse.contents = colorForDensity(point.density)
            
            scene.rootNode.addChildNode(node)
        }
        
        return scene
    }
    
    private func colorForDensity(_ density: Float) -> UIColor {
        switch density {
        case 0..<0.25:
            return .red
        case 0.25..<0.5:
            return .orange
        case 0.5..<0.75:
            return .yellow
        default:
            return .green
        }
    }
}

#if DEBUG
struct CoverageHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        CoverageHeatmapView(
            heatmap: [
                (SIMD3<Float>(0, 0, 0), 1.0),
                (SIMD3<Float>(0.1, 0, 0), 0.75),
                (SIMD3<Float>(-0.1, 0, 0), 0.5),
                (SIMD3<Float>(0, 0.1, 0), 0.25)
            ],
            coverage: 0.65
        )
        .preferredColorScheme(.dark)
    }
}