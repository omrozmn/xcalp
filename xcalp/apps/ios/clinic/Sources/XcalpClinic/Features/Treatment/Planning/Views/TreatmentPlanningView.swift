import ComposableArchitecture
import SceneKit
import SwiftUI

struct TreatmentPlanningView: View {
    let store: StoreOf<TreatmentPlanningFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                if let scan = viewStore.currentScan {
                    SceneView(
                        scene: createScene(with: scan, plan: viewStore.generatedPlan),
                        options: [.allowsCameraControl, .autoenablesDefaultLighting]
                    )
                    .frame(height: 300)
                } else {
                    ContentUnavailableView(
                        "No Scan Selected",
                        systemImage: "cube.transparent",
                        description: Text("Please select a patient scan to continue")
                    )
                    .frame(height: 300)
                }
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 16) {
                        templateSelectionSection(viewStore)
                        
                        if viewStore.selectedTemplate != nil {
                            planningActionsSection(viewStore)
                        }
                        
                        if let plan = viewStore.generatedPlan {
                            planDetailsSection(plan)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Treatment Planning")
            .alert(
                "Error",
                isPresented: .constant(viewStore.error != nil),
                actions: {
                    Button("OK") {
                        viewStore.send(.setError(nil))
                    }
                },
                message: {
                    Text(viewStore.error ?? "")
                }
            )
            .onAppear {
                viewStore.send(.loadTemplates)
            }
        }
    }
    
    private func templateSelectionSection(_ viewStore: ViewStore<TreatmentPlanningFeature.State, TreatmentPlanningFeature.Action>) -> some View {
        VStack(alignment: .leading) {
            Text("Treatment Template")
                .font(.headline)
            
            Menu {
                ForEach(viewStore.availableTemplates) { template in
                    Button {
                        viewStore.send(.selectTemplate(template))
                    } label: {
                        HStack {
                            Text(template.name)
                            if viewStore.selectedTemplate?.id == template.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewStore.selectedTemplate?.name ?? "Select Template")
                        .foregroundColor(viewStore.selectedTemplate == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    private func planningActionsSection(_ viewStore: ViewStore<TreatmentPlanningFeature.State, TreatmentPlanningFeature.Action>) -> some View {
        VStack(spacing: 12) {
            Button {
                viewStore.send(.generatePlan)
            } label: {
                if viewStore.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Label("Generate Plan", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewStore.currentScan == nil || viewStore.isGenerating)
            
            if viewStore.currentScan == nil {
                Text("Select a patient scan to generate plan")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func planDetailsSection(_ plan: TreatmentPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan Details")
                .font(.headline)
            
            Group {
                DetailRow(
                    icon: "number.circle.fill",
                    label: "Total Grafts",
                    value: "\(plan.totalGrafts)"
                )
                
                DetailRow(
                    icon: "ruler.fill",
                    label: "Safe Region",
                    value: "A: \(plan.safeRegion.anteriorMargin)mm P: \(plan.safeRegion.posteriorMargin)mm"
                )
                
                DetailRow(
                    icon: "clock.fill",
                    label: "Created",
                    value: plan.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func createScene(with scan: ScanData, plan: TreatmentPlan?) -> SCNScene {
        let scene = SCNScene()
        
        // Add scan geometry
        let scanNode = SCNNode(geometry: scan.mesh)
        scanNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGray
        
        // Add plan visualization if available
        if let plan = plan {
            let planNode = createPlanVisualization(plan)
            scanNode.addChildNode(planNode)
        }
        
        scene.rootNode.addChildNode(scanNode)
        return scene
    }
    
    private func createPlanVisualization(_ plan: TreatmentPlan) -> SCNNode {
        let node = SCNNode()
        
        // Add safe region visualization
        let safeRegionNode = createSafeRegionNode(plan.safeRegion)
        node.addChildNode(safeRegionNode)
        
        // Add density and angle indicators
        addDensityVisualization(to: node, with: plan.densityMap)
        addAngleVisualization(to: node, with: plan.angleMap)
        
        return node
    }
    
    private func createSafeRegionNode(_ region: SafeRegion) -> SCNNode {
        let box = SCNBox(
            width: CGFloat(region.bounds.max.x - region.bounds.min.x),
            height: CGFloat(region.bounds.max.y - region.bounds.min.y),
            length: CGFloat(region.bounds.max.z - region.bounds.min.z),
            chamferRadius: 0
        )
        box.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.2)
        box.firstMaterial?.isDoubleSided = true
        
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            (region.bounds.max.x + region.bounds.min.x) / 2,
            (region.bounds.max.y + region.bounds.min.y) / 2,
            (region.bounds.max.z + region.bounds.min.z) / 2
        )
        return node
    }
    
    private func addDensityVisualization(to node: SCNNode, with densityMap: DensityMap) {
        // Add density visualization using particle system or color gradient
        let particleSystem = SCNParticleSystem()
        particleSystem.particleSize = 0.5
        particleSystem.particleColor = .systemBlue
        particleSystem.birthRate = 500
        particleSystem.emissionDuration = 1
        particleSystem.spreadingAngle = 45
        
        let emitterNode = SCNNode()
        emitterNode.addParticleSystem(particleSystem)
        node.addChildNode(emitterNode)
    }
    
    private func addAngleVisualization(to node: SCNNode, with angleMap: AngleMap) {
        // Add arrow indicators for hair angles
        let createArrow = { (angle: Double, position: SCNVector3) -> SCNNode in
            let arrow = SCNNode()
            let line = SCNCylinder(radius: 0.2, height: 2)
            line.firstMaterial?.diffuse.contents = UIColor.systemGreen
            
            let lineNode = SCNNode(geometry: line)
            lineNode.eulerAngles.x = Float(angle) * .pi / 180
            lineNode.position = position
            
            arrow.addChildNode(lineNode)
            return arrow
        }
        
        // Add arrows for different regions
        node.addChildNode(createArrow(angleMap.crown, SCNVector3(0, 2, 0)))
        node.addChildNode(createArrow(angleMap.hairline, SCNVector3(0, 1, 1)))
        node.addChildNode(createArrow(angleMap.temporal, SCNVector3(1, 1, 0)))
    }
}

private struct DetailRow: View {
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
