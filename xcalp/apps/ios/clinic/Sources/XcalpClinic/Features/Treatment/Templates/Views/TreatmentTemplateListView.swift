import SwiftUI
import ComposableArchitecture

struct TreatmentTemplateListView: View {
    let store: StoreOf<TreatmentTemplateFeature>
    @State private var previewTemplate: TreatmentTemplate?
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            List {
                ForEach(viewStore.templates) { template in
                    VStack(alignment: .leading) {
                        TemplateRowView(template: template)
                            .onTapGesture {
                                viewStore.send(.selectTemplate(template))
                            }
                        
                        Button {
                            previewTemplate = template
                        } label: {
                            Label("Preview Template", systemImage: "eye.fill")
                                .font(.footnote)
                                .foregroundColor(.blue)
                        }
                        .padding(.leading)
                    }
                }
            }
            .navigationTitle("Treatment Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Template") {
                        viewStore.send(.createNewTemplate)
                    }
                }
            }
            .sheet(item: $previewTemplate) { template in
                NavigationView {
                    TreatmentTemplatePreviewView(template: template)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    previewTemplate = nil
                                }
                            }
                        }
                }
            }
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
}

private struct TemplateRowView: View {
    let template: TreatmentTemplate
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(template.name)
                .font(.headline)
            Text(template.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Label("\(Int(template.parameters.targetDensity)) grafts/cm²", 
                      systemImage: "chart.bar.fill")
                Spacer()
                Text(template.updatedAt, style: .date)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}