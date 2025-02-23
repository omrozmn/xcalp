import SwiftUI
import ComposableArchitecture

struct TemplateVersionHistoryView: View {
    let store: StoreOf<TreatmentTemplateFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            List(viewStore.templateVersions) { template in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Version \(template.version)")
                            .xcalpText(.h3)
                        Spacer()
                        Text(template.createdAt.formatted(.relative))
                            .xcalpText(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if template.version != viewStore.selectedTemplate?.version {
                        Button("Restore This Version") {
                            viewStore.send(.restoreVersion(template))
                        }
                        .buttonStyle(XcalpButton(style: .secondary))
                        .disabled(viewStore.isSaving)
                    }
                    
                    Divider()
                    
                    Text("Parameters")
                        .xcalpText(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(template.parameters) { parameter in
                        Text("\(parameter.name): \(parameter.value ?? "Not set")")
                            .xcalpText(.body)
                    }
                    
                    Text("Regions")
                        .xcalpText(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(template.regions) { region in
                        Text("\(region.name) (\(region.type.rawValue))")
                            .xcalpText(.body)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewStore.isSaving)
            .overlay {
                if viewStore.isSaving {
                    ProgressView("Restoring version...")
                }
            }
        }
    }
}