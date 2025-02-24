import ComposableArchitecture
import SwiftUI

struct TreatmentTemplateEditorView: View {
    @ObservedObject var viewStore: ViewStore<TreatmentTemplateFeature.State, TreatmentTemplateFeature.Action>
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Basic Information
                    VStack(alignment: .leading, spacing: 16) {
                        if let template = viewStore.selectedTemplate {
                            TextField("Template Name", text: Binding(
                                get: { template.name },
                                set: { viewStore.send(.updateName($0)) }
                            ))
                            .xcalpTextField()
                            
                            TextEditor(text: Binding(
                                get: { template.description },
                                set: { viewStore.send(.updateDescription($0)) }
                            ))
                            .frame(height: 100)
                            .xcalpTextField()
                        }
                    }
                    .xcalpCard()
                    
                    // Parameters Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Parameters")
                                .xcalpText(.h2)
                            Spacer()
                            Button {
                                viewStore.send(.showParameterCreator)
                            } label: {
                                Label("Add Parameter", systemImage: "plus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(BrandConstants.Colors.vibrantBlue)
                            }
                        }
                        
                        if let template = viewStore.selectedTemplate {
                            if template.parameters.isEmpty {
                                ContentUnavailableView {
                                    Label("No Parameters", systemImage: "slider.horizontal.3")
                                } description: {
                                    Text("Add parameters to customize the treatment template")
                                }
                            } else {
                                ForEach(template.parameters) { parameter in
                                    ParameterEditor(
                                        parameter: parameter,
                                        onUpdate: { updatedParameter in
                                            viewStore.send(.updateParameter(updatedParameter))
                                        },
                                        onDelete: {
                                            viewStore.send(.deleteParameter(parameter))
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .xcalpCard()
                    
                    // Regions Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Regions")
                                .xcalpText(.h2)
                            Spacer()
                            Button {
                                viewStore.send(.showRegionCreator)
                            } label: {
                                Label("Add Region", systemImage: "plus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(BrandConstants.Colors.vibrantBlue)
                            }
                        }
                        
                        if let template = viewStore.selectedTemplate {
                            if template.regions.isEmpty {
                                ContentUnavailableView {
                                    Label("No Regions", systemImage: "circle.grid.cross")
                                } description: {
                                    Text("Add regions to define treatment areas")
                                }
                            } else {
                                ForEach(template.regions) { region in
                                    RegionEditor(
                                        region: region,
                                        onUpdate: { updatedRegion in
                                            viewStore.send(.updateRegion(updatedRegion))
                                        },
                                        onDelete: {
                                            viewStore.send(.deleteRegion(region))
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .xcalpCard()
                    
                    // Save Button
                    VStack {
                        if viewStore.isSaving {
                            ProgressView("Saving Template...")
                                .xcalpText(.body)
                        } else {
                            Button("Save Template") {
                                viewStore.send(.saveTemplate)
                            }
                            .buttonStyle(XcalpButton(style: .primary))
                            .disabled(!isValid)
                        }
                        
                        if !isValid {
                            ValidationErrorView(errors: validationErrors)
                        }
                    }
                    .padding(.vertical)
                }
                .padding(.horizontal)
            }
            .background(BrandConstants.Colors.lightBackground)
            .navigationTitle(viewStore.selectedTemplate?.name ?? "New Template")
            .navigationBarTitleDisplayMode(.inline)
            .xcalpNavigationBar()
            .toolbar {
                if let template = viewStore.selectedTemplate {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                viewStore.send(.deleteTemplate(template))
                            } label: {
                                Label("Delete Template", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.white)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: .init(
            get: { viewStore.showingParameterCreator },
            set: { if !$0 { viewStore.send(.hideParameterCreator) } }
        )) {
            ParameterCreatorView(
                onSave: { parameter in
                    viewStore.send(.addParameter(parameter))
                },
                onCancel: {
                    viewStore.send(.hideParameterCreator)
                }
            )
        }
        .sheet(isPresented: .init(
            get: { viewStore.showingRegionCreator },
            set: { if !$0 { viewStore.send(.hideRegionCreator) } }
        )) {
            RegionCreatorView(
                onSave: { region in
                    viewStore.send(.addRegion(region))
                },
                onCancel: {
                    viewStore.send(.hideRegionCreator)
                }
            )
        }
    }
    
    private var isValid: Bool {
        viewStore.selectedTemplate?.isValid ?? false
    }
    
    private var validationErrors: [String] {
        guard let template = viewStore.selectedTemplate else { return [] }
        var errors: [String] = []
        
        if template.name.isEmpty {
            errors.append("Template name is required")
        }
        if template.description.isEmpty {
            errors.append("Template description is required")
        }
        if template.parameters.isEmpty {
            errors.append("At least one parameter is required")
        }
        if template.regions.isEmpty {
            errors.append("At least one region is required")
        }
        
        // Parameter validation
        for parameter in template.parameters where parameter.isRequired {
            if parameter.value == nil {
                errors.append("Parameter '\(parameter.name)' is required")
            }
        }
        
        // Region validation
        for region in template.regions {
            if !region.isValid {
                errors.append("Region '\(region.name)' has invalid parameters")
            }
        }
        
        return errors
    }
}

private struct ValidationErrorView: View {
    let errors: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(BrandConstants.Colors.errorRed)
            }
        }
        .padding()
        .background(BrandConstants.Colors.errorRed.opacity(0.1))
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct ParameterEditor: View {
    let parameter: TreatmentTemplate.Parameter
    let onUpdate: (TreatmentTemplate.Parameter) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(parameter.name)
                    .xcalpText(.h3)
                if parameter.isRequired {
                    Text("Required")
                        .xcalpText(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BrandConstants.Colors.vibrantBlue.opacity(0.1))
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                        .cornerRadius(BrandConstants.Layout.cornerRadius)
                }
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Parameter", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandConstants.Colors.metallicGray)
                }
            }
            
            if let description = parameter.description {
                Text(description)
                    .xcalpText(.caption)
                    .foregroundColor(BrandConstants.Colors.metallicGray)
            }
            
            ParameterValueEditor(parameter: parameter) { newValue in
                var updated = parameter
                updated.value = newValue
                onUpdate(updated)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct ParameterValueEditor: View {
    let parameter: TreatmentTemplate.Parameter
    let onValueChanged: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch parameter.type {
            case .number, .measurement, .density:
                HStack {
                    TextField("Value", text: Binding(
                        get: { parameter.value ?? "" },
                        set: { onValueChanged($0) }
                    ))
                    .xcalpTextField()
                    .keyboardType(.decimalPad)
                    
                    if let unit = parameter.range?.unit {
                        Text(unit)
                            .xcalpText(.caption)
                    }
                }
                
                if let range = parameter.range {
                    if let min = range.minimum, let max = range.maximum {
                        HStack(spacing: 16) {
                            Label {
                                Text("Range: \(min, specifier: "%.1f") - \(max, specifier: "%.1f")")
                                    .xcalpText(.small)
                            } icon: {
                                Image(systemName: "ruler")
                                    .foregroundColor(BrandConstants.Colors.metallicGray)
                            }
                        }
                    }
                }
                
            case .direction:
                HStack {
                    TextField("Angle", text: Binding(
                        get: { parameter.value ?? "" },
                        set: { onValueChanged($0) }
                    ))
                    .xcalpTextField()
                    .keyboardType(.decimalPad)
                    Text("degrees")
                        .xcalpText(.caption)
                }
                
            case .boolean:
                Toggle("Enabled", isOn: Binding(
                    get: { parameter.value == "true" },
                    set: { onValueChanged($0 ? "true" : "false") }
                ))
                .tint(BrandConstants.Colors.vibrantBlue)
                
            case .selection:
                if let options = parameter.range?.options {
                    Picker("Value", selection: Binding(
                        get: { parameter.value ?? options[0] },
                        set: { onValueChanged($0) }
                    )) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .xcalpTextField()
                }
                
            case .text:
                TextField("Value", text: Binding(
                    get: { parameter.value ?? "" },
                    set: { onValueChanged($0) }
                ))
                .xcalpTextField()
            }
        }
    }
}

private struct RegionEditor: View {
    let region: TreatmentRegion
    let onUpdate: (TreatmentRegion) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(region.name)
                    .xcalpText(.h3)
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Region", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandConstants.Colors.metallicGray)
                }
            }
            
            HStack(spacing: 16) {
                Label {
                    Text("\(region.graftCount) grafts")
                        .xcalpText(.body)
                } icon: {
                    Image(systemName: "number")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
                
                Label {
                    Text("\(Int(region.density)) grafts/cm²")
                        .xcalpText(.body)
                } icon: {
                    Image(systemName: "circle.grid.cross")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
            }
            
            HStack(spacing: 16) {
                Label {
                    Text("\(Int(region.direction.angle))°")
                        .xcalpText(.body)
                } icon: {
                    Image(systemName: "arrow.up.right")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
                
                Label {
                    Text("\(region.direction.depth, specifier: "%.1f")mm")
                        .xcalpText(.body)
                } icon: {
                    Image(systemName: "arrow.down.to.line")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
            }
            
            if !region.environmentalFactors.isEmpty {
                Text("Environmental Factors")
                    .xcalpText(.caption)
                    .padding(.top, 4)
                
                HStack(spacing: 12) {
                    ForEach(region.environmentalFactors, id: \.type) { factor in
                        EnvironmentalFactorTag(factor: factor)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct EnvironmentalFactorTag: View {
    let factor: EnvironmentalFactor
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundColor(BrandConstants.Colors.vibrantBlue)
            Text(factor.type.rawValue.capitalized)
                .xcalpText(.small)
            Text(String(format: "%.1f", factor.impact))
                .xcalpText(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(BrandConstants.Colors.lightSilver)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
    
    private var iconName: String {
        switch factor.type {
        case .sunExposure: return "sun.max"
        case .humidity: return "humidity"
        case .temperature: return "thermometer"
        case .lifestyle: return "figure.walk"
        }
    }
}
