import SwiftUI
import ComposableArchitecture

struct TemplateFilterSystem: View {
    @Binding var searchText: String
    @Binding var selectedFilters: Set<FilterOption>
    @State private var showFilterSheet = false
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case standard = "Standard Templates"
        case custom = "Custom Templates"
        case highDensity = "High Density"
        case lowDensity = "Low Density"
        case environmental = "Environmental Factors"
        case recentlyUpdated = "Recently Updated"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .standard: return "doc.text"
            case .custom: return "doc.badge.plus"
            case .highDensity: return "chart.bar.fill"
            case .lowDensity: return "chart.bar"
            case .environmental: return "leaf"
            case .recentlyUpdated: return "clock"
            }
        }
        
        var groupName: String {
            switch self {
            case .standard, .custom:
                return "Template Type"
            case .highDensity, .lowDensity:
                return "Density Range"
            case .environmental, .recentlyUpdated:
                return "Other Filters"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Search Bar with Medical Context
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(BrandConstants.Colors.metallicGray)
                TextField("Search treatment templates", text: $searchText)
                    .xcalpText(.body)
                    .accessibilityHint("Enter keywords to search for specific treatment templates")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(BrandConstants.Colors.metallicGray)
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(BrandConstants.Layout.cornerRadius)
            
            // Active Filters Display
            if !selectedFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedFilters)) { filter in
                            ActiveFilterTag(
                                filter: filter,
                                onRemove: { selectedFilters.remove(filter) }
                            )
                        }
                        
                        Button("Clear All") {
                            selectedFilters.removeAll()
                        }
                        .xcalpText(.caption)
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    }
                    .padding(.horizontal)
                }
            }
            
            // Filter Button
            Button {
                showFilterSheet = true
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    Text("Filter Templates")
                        .xcalpText(.body)
                    Spacer()
                    if !selectedFilters.isEmpty {
                        Text("\(selectedFilters.count)")
                            .xcalpText(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BrandConstants.Colors.vibrantBlue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(BrandConstants.Layout.cornerRadius)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationView {
                FilterSheetView(selectedFilters: $selectedFilters)
                    .navigationTitle("Filter Templates")
                    .navigationBarTitleDisplayMode(.inline)
                    .xcalpNavigationBar()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showFilterSheet = false
                            }
                            .foregroundColor(.white)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Apply") {
                                showFilterSheet = false
                            }
                            .foregroundColor(.white)
                        }
                    }
            }
        }
    }
}

private struct ActiveFilterTag: View {
    let filter: TemplateFilterSystem.FilterOption
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: filter.icon)
                .font(.system(size: 12))
            Text(filter.rawValue)
                .xcalpText(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(BrandConstants.Colors.metallicGray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BrandConstants.Colors.vibrantBlue.opacity(0.1))
        .foregroundColor(BrandConstants.Colors.darkNavy)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct FilterSheetView: View {
    @Binding var selectedFilters: Set<TemplateFilterSystem.FilterOption>
    
    var filterGroups: [String: [TemplateFilterSystem.FilterOption]] {
        Dictionary(grouping: TemplateFilterSystem.FilterOption.allCases) { $0.groupName }
    }
    
    var body: some View {
        List {
            ForEach(Array(filterGroups.keys.sorted()), id: \.self) { group in
                Section(group) {
                    ForEach(filterGroups[group] ?? []) { option in
                        FilterOptionRow(
                            option: option,
                            isSelected: selectedFilters.contains(option),
                            onToggle: {
                                if selectedFilters.contains(option) {
                                    selectedFilters.remove(option)
                                } else {
                                    selectedFilters.insert(option)
                                }
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct FilterOptionRow: View {
    let option: TemplateFilterSystem.FilterOption
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: option.icon)
                    .foregroundColor(BrandConstants.Colors.vibrantBlue)
                Text(option.rawValue)
                    .xcalpText(.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
            }
        }
        .foregroundColor(BrandConstants.Colors.darkNavy)
    }
}