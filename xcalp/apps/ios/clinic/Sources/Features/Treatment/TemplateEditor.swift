import SwiftUI

struct TemplateEditorView: View {
    let template: TreatmentTemplate?
    let isCreating: Bool
    let onSave: (TreatmentTemplate) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    @State private var description: String
    @State private var targetDensity: Double
    @State private var graftSpacing: Double
    @State private var angleVariation: Double
    @State private var naturalness: Double
    @State private var regions: [TreatmentRegion]
    @State private var selectedRegion: TreatmentRegion?
    @State private var showingRegionEditor = false
    @State private var customParameters: [TreatmentTemplate.Parameter] = []
    @State private var showingCustomParameterEditor = false
    
    init(
        template: TreatmentTemplate?,
        isCreating: Bool,
        onSave: @escaping (TreatmentTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.template = template
        self.isCreating = isCreating
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state from template or defaults
        _name = State(initialValue: template?.name ?? "")
        _description = State(initialValue: template?.description ?? "")
        _targetDensity = State(initialValue: template?.parameters.targetDensity ?? 40.0)
        _graftSpacing = State(initialValue: template?.parameters.graftSpacing ?? 0.8)
        _angleVariation = State(initialValue: template?.parameters.angleVariation ?? 15.0)
        _naturalness = State(initialValue: template?.parameters.naturalness ?? 0.7)
        _regions = State(initialValue: template?.regions ?? [])
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Name", text: $name)
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section(header: Text("Core Parameters")) {
                    VStack(alignment: .leading) {
                        Text("Target Density (grafts/cm²)")
                        Slider(value: $targetDensity, in: 20...60, step: 1) {
                            Text("Target Density")
                        }
                        Text("\(Int(targetDensity)) grafts/cm²")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Graft Spacing (mm)")
                        Slider(value: $graftSpacing, in: 0.5...1.5, step: 0.1) {
                            Text("Graft Spacing")
                        }
                        Text(String(format: "%.1f mm", graftSpacing))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Angle Variation (degrees)")
                        Slider(value: $angleVariation, in: 0...30, step: 1) {
                            Text("Angle Variation")
                        }
                        Text("\(Int(angleVariation))°")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Naturalness")
                        Slider(value: $naturalness, in: 0...1, step: 0.1) {
                            Text("Naturalness")
                        }
                        Text("\(Int(naturalness * 100))%")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: HStack {
                    Text("Custom Parameters")
                    Spacer()
                    Button(action: { showingCustomParameterEditor = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    }
                }) {
                    if customParameters.isEmpty {
                        Text("No custom parameters")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(customParameters) { parameter in
                            CustomParameterRow(parameter: parameter) { updatedParameter in
                                if let index = customParameters.firstIndex(where: { $0.id == parameter.id }) {
                                    customParameters[index] = updatedParameter
                                }
                            } onDelete: {
                                customParameters.removeAll { $0.id == parameter.id }
                            }
                        }
                    }
                }
                
                Section(header: Text("Treatment Regions")) {
                    ForEach(regions) { region in
                        RegionRow(region: region)
                            .contextMenu {
                                Button("Edit") {
                                    selectedRegion = region
                                    showingRegionEditor = true
                                }
                                Button("Delete", role: .destructive) {
                                    regions.removeAll { $0.id == region.id }
                                }
                            }
                    }
                    
                    Button("Add Region") {
                        showingRegionEditor = true
                    }
                }
            }
            .navigationTitle(isCreating ? "New Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showingRegionEditor) {
                RegionEditorView(
                    region: selectedRegion,
                    onSave: { region in
                        if let index = regions.firstIndex(where: { $0.id == region.id }) {
                            regions[index] = region
                        } else {
                            regions.append(region)
                        }
                        selectedRegion = nil
                        showingRegionEditor = false
                    },
                    onCancel: {
                        selectedRegion = nil
                        showingRegionEditor = false
                    }
                )
            }
            .sheet(isPresented: $showingCustomParameterEditor) {
                CustomParameterEditorView { parameter in
                    customParameters.append(parameter)
                    showingCustomParameterEditor = false
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        !description.isEmpty &&
        !regions.isEmpty &&
        targetDensity >= 20 && targetDensity <= 60 &&
        graftSpacing >= 0.5 && graftSpacing <= 1.5 &&
        angleVariation >= 0 && angleVariation <= 30 &&
        naturalness >= 0 && naturalness <= 1 &&
        customParameters.allSatisfy { $0.isValid }
    }
    
    private func saveTemplate() {
        let parameters = TreatmentTemplate.TemplateParameters(
            targetDensity: targetDensity,
            graftSpacing: graftSpacing,
            angleVariation: angleVariation,
            naturalness: naturalness,
            customParameters: Dictionary(uniqueKeysWithValues: customParameters.map { ($0.id, $0) })
        )
        
        let newTemplate = TreatmentTemplate(
            id: template?.id ?? UUID(),
            name: name,
            description: description,
            version: template?.version ?? 1,
            createdAt: template?.createdAt ?? Date(),
            updatedAt: Date(),
            parameters: parameters,
            regions: regions,
            author: "Current User", // TODO: Get from authentication
            isCustom: true,
            parentTemplateId: template?.parentTemplateId
        )
        
        onSave(newTemplate)
    }
}

private struct RegionRow: View {
    let region: TreatmentRegion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(region.name)
                .font(.headline)
            HStack {
                Text(region.type.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Density: \(Int(region.parameters.density))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}