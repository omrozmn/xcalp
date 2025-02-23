import SwiftUI
import SceneKit

struct TreatmentTemplatePreviewView: View {
    let template: TreatmentTemplate
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack {
            SceneView(
                scene: createPreviewScene(),
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .frame(height: 300)
            
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    PreviewMetricRow(
                        icon: "chart.bar.fill",
                        label: "Target Density",
                        value: "\(Int(template.parameters.targetDensity)) grafts/cm²"
                    )
                    
                    PreviewMetricRow(
                        icon: "ruler",
                        label: "Margins",
                        value: "A: \(template.parameters.safetyMargins.anterior)mm P: \(template.parameters.safetyMargins.posterior)mm"
                    )
                    
                    PreviewMetricRow(
                        icon: "angle",
                        label: "Crown Angle",
                        value: "\(Int(template.parameters.anglePreferences.crown))°"
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Template Preview")
    }
    
    private func createPreviewScene() -> SCNScene {
        let scene = SCNScene()
        
        // Create a simplified head model
        let headGeometry = SCNSphere(radius: 0.1)
        let headNode = SCNNode(geometry: headGeometry)
        
        // Add visualization for treatment regions
        addTreatmentRegions(to: headNode)
        
        scene.rootNode.addChildNode(headNode)
        return scene
    }
    
    private func addTreatmentRegions(to headNode: SCNNode) {
        // Add recipient region visualization
        let recipientRegion = SCNBox(
            width: 0.05,
            height: 0.001,
            length: 0.03,
            chamferRadius: 0.005
        )
        recipientRegion.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        
        let recipientNode = SCNNode(geometry: recipientRegion)
        recipientNode.position = SCNVector3(0, 0.09, 0)
        recipientNode.eulerAngles.x = Float(-template.parameters.anglePreferences.crown) * .pi / 180
        
        // Add donor region visualization
        let donorRegion = SCNBox(
            width: 0.04,
            height: 0.001,
            length: 0.02,
            chamferRadius: 0.005
        )
        donorRegion.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.3)
        
        let donorNode = SCNNode(geometry: donorRegion)
        donorNode.position = SCNVector3(0, -0.02, -0.08)
        
        headNode.addChildNode(recipientNode)
        headNode.addChildNode(donorNode)
    }
}

private struct PreviewMetricRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(label)
            Spacer()
            Text(value)
                .bold()
        }
    }
}