import Dependencies
import SwiftUI

struct RegionEditorView: View {
    let region: TreatmentRegion?
    let onSave: (TreatmentRegion) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    @State private var type: TreatmentRegion.RegionType
    @State private var density: Double
    @State private var direction: Direction3D
    @State private var depth: Double
    @State private var boundaries: [Point3D]
    @State private var selectedTab = 0
    @State private var scanModelURL: URL?
    @State private var isLoadingModel = false
    @State private var modelError: String?
    
    @Dependency(\.scanModelManager) private var scanModelManager
    
    init(
        region: TreatmentRegion?,
        onSave: @escaping (TreatmentRegion) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.region = region
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state from region or defaults
        _name = State(initialValue: region?.name ?? "")
        _type = State(initialValue: region?.type ?? .recipient)
        _density = State(initialValue: region?.parameters.density ?? 40.0)
        _direction = State(initialValue: region?.parameters.direction ?? Direction3D(x: 0, y: 1, z: 0))
        _depth = State(initialValue: region?.parameters.depth ?? 4.0)
        _boundaries = State(initialValue: region?.boundaries ?? [])
    }
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Parameters Tab
                parametersView
                    .tabItem {
                        Label("Parameters", systemImage: "slider.horizontal.3")
                    }
                    .tag(0)
                
                // Boundary Editor Tab
                boundaryEditorView
                    .tabItem {
                        Label("Region", systemImage: "square.dashed")
                    }
                    .tag(1)
            }
            .navigationTitle(region == nil ? "New Region" : "Edit Region")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRegion()
                    }
                    .disabled(!isValid)
                }
            }
            .task {
                await loadScanModel()
            }
            .alert("Error", isPresented: .init(
                get: { modelError != nil },
                set: { if !$0 { modelError = nil } }
            )) {
                Text(modelError ?? "")
            }
        }
    }
    
    private var parametersView: some View {
        Form {
            Section(header: Text("Basic Information")) {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    Text("Recipient").tag(TreatmentRegion.RegionType.recipient)
                    Text("Donor").tag(TreatmentRegion.RegionType.donor)
                }
            }
            
            Section(header: Text("Parameters")) {
                VStack(alignment: .leading) {
                    Text("Density (grafts/cm²)")
                    Slider(value: $density, in: 20...60, step: 1)
                    Text("\(Int(density))")
                }
                
                VStack(alignment: .leading) {
                    Text("Depth (mm)")
                    Slider(value: $depth, in: 2...6, step: 0.1)
                    Text(String(format: "%.1f", depth))
                }
            }
            
            Section(header: Text("Direction")) {
                DirectionEditor(direction: $direction)
            }
        }
    }
    
    private var boundaryEditorView: some View {
        ZStack {
            if isLoadingModel {
                ProgressView("Loading 3D Model...")
            } else {
                RegionBoundaryEditor(
                    boundaries: $boundaries,
                    modelURL: scanModelURL
                )
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty && boundaries.count >= 3
    }
    
    private func saveRegion() {
        let parameters = TreatmentRegion.RegionParameters(
            density: density,
            direction: direction.normalized,
            depth: depth,
            customParameters: [:]
        )
        
        let newRegion = TreatmentRegion(
            id: region?.id ?? UUID(),
            name: name,
            type: type,
            boundaries: boundaries,
            parameters: parameters
        )
        
        onSave(newRegion)
    }
    
    private func loadScanModel() async {
        isLoadingModel = true
        defer { isLoadingModel = false }
        
        do {
            if let url = await scanModelManager.getCurrentScan() {
                try await scanModelManager.validateScanModel(url)
                scanModelURL = url
            }
        } catch {
            modelError = error.localizedDescription
        }
    }
}

private struct DirectionEditor: View {
    @Binding var direction: Direction3D
    
    var body: some View {
        VStack(spacing: 16) {
            DirectionSlider(value: .init(
                get: { direction.x },
                set: { direction = Direction3D(x: $0, y: direction.y, z: direction.z) }
            ), label: "X")
            
            DirectionSlider(value: .init(
                get: { direction.y },
                set: { direction = Direction3D(x: direction.x, y: $0, z: direction.z) }
            ), label: "Y")
            
            DirectionSlider(value: .init(
                get: { direction.z },
                set: { direction = Direction3D(x: direction.x, y: direction.y, z: $0) }
            ), label: "Z")
        }
    }
}

private struct DirectionSlider: View {
    @Binding var value: Double
    let label: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(label) Axis")
            Slider(value: $value, in: -1...1, step: 0.1)
            Text(String(format: "%.1f", value))
        }
    }
}
