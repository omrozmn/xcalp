import ComposableArchitecture
import SwiftUI

struct TemplateSelectionView: View {
    let store: StoreOf<TreatmentFeature>
    @State private var searchText = ""
    @State private var selectedCategory: TemplateCategory = .all
    
    enum TemplateCategory: String, CaseIterable {
        case all = "All"
        case standard = "Standard"
        case custom = "Custom"
        case recent = "Recent"
    }
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 20) {
                // Search and Filter
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(BrandConstants.Colors.metallicGray)
                        TextField("Search templates", text: $searchText)
                            .xcalpText(.body)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(BrandConstants.Layout.cornerRadius)
                    .shadow(color: BrandConstants.Colors.darkGray.opacity(0.05), radius: 4)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(TemplateCategory.allCases, id: \.self) { category in
                                CategoryButton(
                                    title: category.rawValue,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = category
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Templates Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(viewStore.templateFeature.templates) { template in
                        TemplateGridItem(template: template) {
                            viewStore.send(.applyTemplate(template))
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .xcalpText(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? BrandConstants.Colors.vibrantBlue : Color.white)
                .foregroundColor(isSelected ? .white : BrandConstants.Colors.darkNavy)
                .cornerRadius(BrandConstants.Layout.cornerRadius)
                .shadow(color: BrandConstants.Colors.darkGray.opacity(0.05), radius: 4)
        }
    }
}

private struct TemplateGridItem: View {
    let template: TreatmentTemplate
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: template.isCustom ? "doc.badge.plus" : "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    Spacer()
                    Text("v\(template.version)")
                        .xcalpText(.small)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.name)
                        .xcalpText(.h3)
                        .lineLimit(1)
                    
                    if !template.description.isEmpty {
                        Text(template.description)
                            .xcalpText(.caption)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    // Footer
                    HStack {
                        Label {
                            Text("\(template.parameters.count)")
                                .xcalpText(.small)
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(BrandConstants.Colors.vibrantBlue)
                        }
                        
                        Label {
                            Text("\(template.regions.count)")
                                .xcalpText(.small)
                        } icon: {
                            Image(systemName: "circle.grid.cross")
                                .foregroundColor(BrandConstants.Colors.vibrantBlue)
                        }
                    }
                }
            }
            .frame(height: 160)
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
        .buttonStyle(.plain)
    }
}
