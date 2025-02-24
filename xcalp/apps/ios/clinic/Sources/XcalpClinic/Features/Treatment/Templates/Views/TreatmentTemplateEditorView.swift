import ComposableArchitecture
import SwiftUI

struct TreatmentTemplateEditorView: View {
    let store: StoreOf<TreatmentTemplateFeature>
    @State private var templateData: TemplateFormData
    
    init(store: StoreOf<TreatmentTemplateFeature>) {
        self.store = store
        let viewStore = ViewStore(store, observe: { $0 })
        _templateData = State(initialValue: TemplateFormData(template: viewStore.selectedTemplate))
    }
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            Form {
                Section("Basic Information") {
                    TextField("Template Name", text: $templateData.name)
                    TextField("Description", text: $templateData.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Treatment Parameters") {
                    HStack {
                        Text("Target Density")
                        Spacer()
                        TextField("grafts/cm²", value: $templateData.targetDensity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    NavigationLink("Safety Margins") {
                        MarginEditorView(margins: $templateData.margins)
                    }
                    
                    NavigationLink("Angle Preferences") {
                        AnglePreferencesView(angles: $templateData.angles)
                    }
                }
                
                Section("Region Specifications") {
                    NavigationLink("Donor Region") {
                        DonorRegionView(donor: $templateData.donor)
                    }
                    
                    NavigationLink("Recipient Region") {
                        RecipientRegionView(recipient: $templateData.recipient)
                    }
                }
            }
            .navigationTitle(viewStore.isCreatingNew ? "New Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let template = templateData.toTemplate(
                            id: viewStore.selectedTemplate?.id ?? UUID(),
                            createdAt: viewStore.selectedTemplate?.createdAt ?? Date()
                        )
                        if viewStore.isCreatingNew {
                            viewStore.send(.saveTemplate(template))
                        } else {
                            viewStore.send(.updateTemplate(template))
                        }
                    }
                    .disabled(!templateData.isValid)
                }
                
                if !viewStore.isCreatingNew {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            if let template = viewStore.selectedTemplate {
                                viewStore.send(.deleteTemplate(template))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TemplateFormData {
    var name: String = ""
    var description: String = ""
    var targetDensity: Double = 30.0
    var margins = TreatmentTemplate.Margins(anterior: 5, posterior: 5, lateral: 5)
    var angles = TreatmentTemplate.AnglePreferences(crown: 45, hairline: 30, temporal: 35)
    var donor = TreatmentTemplate.DonorRegion(
        safeExtractionDepth: 4,
        maxGraftDensity: 35,
        minimumFollicleSpacing: 1
    )
    var recipient = TreatmentTemplate.RecipientRegion(
        targetHairlinePosition: 8,
        naturalAngleVariation: 5,
        densityGradient: 5
    )
    
    init(template: TreatmentTemplate? = nil) {
        if let template = template {
            name = template.name
            description = template.description
            targetDensity = template.parameters.targetDensity
            margins = template.parameters.safetyMargins
            angles = template.parameters.anglePreferences
            donor = template.parameters.regionSpecifications.donor
            recipient = template.parameters.regionSpecifications.recipient
        }
    }
    
    var isValid: Bool {
        !name.isEmpty && targetDensity > 0
    }
    
    func toTemplate(id: UUID, createdAt: Date) -> TreatmentTemplate {
        TreatmentTemplate(
            id: id,
            name: name,
            description: description,
            parameters: TreatmentTemplate.TreatmentParameters(
                targetDensity: targetDensity,
                safetyMargins: margins,
                anglePreferences: angles,
                regionSpecifications: TreatmentTemplate.RegionSpecifications(
                    donor: donor,
                    recipient: recipient
                )
            ),
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
