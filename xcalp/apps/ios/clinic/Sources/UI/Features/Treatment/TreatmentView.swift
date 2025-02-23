import SwiftUI
import ComposableArchitecture

struct TreatmentView: View {
    let store: StoreOf<TreatmentFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationSplitView {
                TreatmentTemplateListView(
                    store: store.scope(
                        state: \.templateFeature,
                        action: TreatmentFeature.Action.templateFeature
                    )
                )
            } detail: {
                if let treatment = viewStore.currentTreatment {
                    ScrollView {
                        VStack(spacing: 20) {
                            if let template = treatment.appliedTemplate {
                                TemplateInfoCard(template: template)
                            } else {
                                SelectTemplateCard {
                                    // TODO: Show template selection
                                }
                            }
                            
                            RegionsEditor(
                                regions: treatment.regions,
                                onChange: { regions in
                                    viewStore.send(.updateRegions(regions))
                                }
                            )
                            
                            NotesEditor(
                                notes: treatment.notes,
                                onChange: { notes in
                                    viewStore.send(.updateNotes(notes))
                                }
                            )
                            
                            Button("Save Treatment") {
                                viewStore.send(.saveTreatment)
                            }
                            .buttonStyle(XcalpButton(style: .primary))
                            .disabled(treatment.regions.isEmpty)
                        }
                        .padding()
                    }
                    .background(BrandConstants.Colors.lightBackground)
                    .navigationTitle("Treatment Plan")
                    .xcalpNavigationBar()
                } else {
                    ContentUnavailableView(
                        "No Treatment Selected",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Select a patient to create or view their treatment plan")
                    )
                    .xcalpNavigationBar()
                }
            }
            .alert(
                "Error",
                isPresented: .constant(viewStore.error != nil),
                actions: {
                    Button("OK") {
                        viewStore.send(.dismissError)
                    }
                },
                message: {
                    Text(viewStore.error ?? "")
                }
            )
        }
    }
}

private struct TemplateInfoCard: View {
    let template: TreatmentTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Applied Template")
                        .xcalpText(.h3)
                    Text(template.name)
                        .xcalpText(.h2)
                }
                Spacer()
                Text("v\(template.version)")
                    .xcalpText(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandConstants.Colors.lightSilver)
                    .cornerRadius(BrandConstants.Layout.cornerRadius)
            }
            
            if !template.description.isEmpty {
                Text(template.description)
                    .xcalpText(.body)
            }
            
            HStack(spacing: 16) {
                Label {
                    Text("\(template.parameters.count) parameters")
                        .xcalpText(.caption)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
                
                Label {
                    Text("\(template.regions.count) regions")
                        .xcalpText(.caption)
                } icon: {
                    Image(systemName: "circle.grid.cross")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
                
                Spacer()
                
                Text(template.updatedAt.formatted(.relative))
                    .xcalpText(.small)
            }
        }
        .xcalpCard()
    }
}

private struct SelectTemplateCard: View {
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(BrandConstants.Colors.vibrantBlue)
                
                Text("Select Template")
                    .xcalpText(.h3)
                
                Text("Choose a treatment template to get started")
                    .xcalpText(.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .xcalpCard()
    }
}

private struct RegionsEditor: View {
    let regions: [TreatmentRegion]
    let onChange: ([TreatmentRegion]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Treatment Regions")
                    .xcalpText(.h2)
                Spacer()
                Button {
                    // TODO: Add region
                } label: {
                    Label("Add Region", systemImage: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandConstants.Colors.vibrantBlue)
                }
            }
            
            if regions.isEmpty {
                ContentUnavailableView {
                    Label("No Regions", systemImage: "circle.grid.cross")
                } description: {
                    Text("Add regions to define treatment areas")
                }
            } else {
                ForEach(regions) { region in
                    RegionCard(region: region)
                }
            }
        }
        .xcalpCard()
    }
}

private struct RegionCard: View {
    let region: TreatmentRegion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(region.name)
                    .xcalpText(.h3)
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        // TODO: Delete region
                    } label: {
                        Label("Delete Region", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandConstants.Colors.metallicGray)
                }
            }
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
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
                
                GridRow {
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
            }
            
            if !region.environmentalFactors.isEmpty {
                Text("Environmental Factors")
                    .xcalpText(.caption)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(region.environmentalFactors, id: \.type) { factor in
                            EnvironmentalFactorTag(factor: factor)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct NotesEditor: View {
    let notes: String
    let onChange: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Treatment Notes")
                .xcalpText(.h2)
            
            TextEditor(text: Binding(
                get: { notes },
                set: { onChange($0) }
            ))
            .frame(height: 120)
            .xcalpTextField()
        }
        .xcalpCard()
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