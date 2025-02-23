import SwiftUI
import ComposableArchitecture

struct TreatmentTemplateListView: View {
    let store: StoreOf<TreatmentTemplateFeature>
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            List {
                ForEach(viewStore.templates) { template in
                    TemplateRowView(template: template)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewStore.send(.selectTemplate(template))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .background(BrandConstants.Colors.lightBackground)
            .navigationTitle("Treatment Templates")
            .xcalpNavigationBar()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewStore.send(.createTemplate)
                    } label: {
                        Label("Create Template", systemImage: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(BrandConstants.Colors.vibrantBlue)
                    }
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

private struct TemplateRowView: View {
    let template: TreatmentTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(template.name)
                    .xcalpText(.h3)
                
                if template.isCustom {
                    Text("Custom")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BrandConstants.Colors.vibrantBlue.opacity(0.1))
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                        .cornerRadius(BrandConstants.Layout.cornerRadius)
                }
                
                Spacer()
                
                Text("v\(template.version)")
                    .xcalpText(.caption)
            }
            
            if !template.description.isEmpty {
                Text(template.description)
                    .xcalpText(.body)
                    .lineLimit(2)
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
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
        .shadow(
            color: BrandConstants.Colors.darkGray.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}