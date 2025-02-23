import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct TemplateList: ReducerProtocol {
    struct State: Equatable {
        var templates: [TreatmentTemplate] = []
        var selectedTemplate: TreatmentTemplate?
        var isEditing = false
        var isCreating = false
        var isImporting = false
        var isExporting = false
        var error: String?
        var showingRecommendations = false
    }
    
    enum Action: Equatable {
        case onAppear
        case templatesLoaded([TreatmentTemplate])
        case createTemplate
        case editTemplate(TreatmentTemplate)
        case deleteTemplate(TreatmentTemplate)
        case closeEditor
        case errorOccurred(String)
        case templateSaved(TreatmentTemplate)
        case templateDeleted(UUID)
        case importTemplates
        case exportTemplates
        case createBackup
        case templatesImported([TreatmentTemplate])
        case backupCreated(URL)
        case showRecommendations
        case hideRecommendations
        case useRecommendedTemplate(TreatmentTemplate)
    }
    
    @Dependency(\.templateClient) var templateClient
    @Dependency(\.templateManager) var templateManager
    
    var body: some ReducerProtocol<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    do {
                        let templates = try await templateClient.loadTemplates()
                        await send(.templatesLoaded(templates))
                    } catch {
                        await send(.errorOccurred(error.localizedDescription))
                    }
                }
                
            case let .templatesLoaded(templates):
                state.templates = templates
                return .none
                
            case .createTemplate:
                state.isCreating = true
                state.selectedTemplate = nil
                return .none
                
            case let .editTemplate(template):
                state.isEditing = true
                state.selectedTemplate = template
                return .none
                
            case let .deleteTemplate(template):
                return .run { send in
                    do {
                        let success = try await templateClient.deleteTemplate(template.id)
                        if success {
                            await send(.templateDeleted(template.id))
                        }
                    } catch {
                        await send(.errorOccurred(error.localizedDescription))
                    }
                }
                
            case .closeEditor:
                state.isEditing = false
                state.isCreating = false
                state.selectedTemplate = nil
                return .none
                
            case let .errorOccurred(error):
                state.error = error
                // Reset states after an error occurs
                state.isEditing = false
                state.isCreating = false
                return .none
                
            case let .templateSaved(template):
                if let index = state.templates.firstIndex(where: { $0.id == template.id }) {
                    state.templates[index] = template
                } else {
                    state.templates.append(template)
                }
                state.isEditing = false
                state.isCreating = false
                return .none
                
            case let .templateDeleted(id):
                state.templates.removeAll { $0.id == id }
                return .none
                
            case .importTemplates:
                state.isImporting = true
                return .none
                
            case .exportTemplates:
                state.isExporting = true
                return .none
                
            case .createBackup:
                return .run { send in
                    do {
                        let backupURL = try await templateManager.createBackup()
                        await send(.backupCreated(backupURL))
                    } catch {
                        await send(.errorOccurred(error.localizedDescription))
                    }
                }
                
            case let .templatesImported(templates):
                state.templates.append(contentsOf: templates)
                state.isImporting = false
                return .none
                
            case let .backupCreated(url):
                return .none
                
            case .showRecommendations:
                state.showingRecommendations = true
                return .none
                
            case .hideRecommendations:
                state.showingRecommendations = false
                return .none
                
            case let .useRecommendedTemplate(template):
                state.showingRecommendations = false
                state.isCreating = true
                state.selectedTemplate = template
                return .none
            }
        }
    }
}

struct TemplateListView: View {
    let store: StoreOf<TemplateList>
    @State private var showingDocumentPicker = false
    @State private var documentPickerMode: DocumentPickerMode = .import
    
    enum DocumentPickerMode {
        case `import`, export
    }
    
    var body: some View {
        WithViewStore(store) { viewStore in
            List {
                ForEach(viewStore.templates) { template in
                    TemplateRow(template: template)
                        .contextMenu {
                            Button("Edit") {
                                viewStore.send(.editTemplate(template))
                            }
                            Button("Delete", role: .destructive) {
                                viewStore.send(.deleteTemplate(template))
                            }
                        }
                        .onTapGesture {
                            viewStore.send(.editTemplate(template))
                        }
                }
            }
            .navigationTitle("Treatment Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create Template") {
                            viewStore.send(.showRecommendations)
                        }
                        
                        Button("Import Templates") {
                            documentPickerMode = .import
                            showingDocumentPicker = true
                        }
                        
                        Button("Export Templates") {
                            documentPickerMode = .export
                            showingDocumentPicker = true
                        }
                        
                        Button("Create Backup") {
                            viewStore.send(.createBackup)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(
                    mode: documentPickerMode,
                    store: store
                )
            }
            .sheet(isPresented: .init(
                get: { viewStore.showingRecommendations },
                set: { if !$0 { viewStore.send(.hideRecommendations) } }
            )) {
                NavigationView {
                    TemplateRecommendationsView(
                        store: store,
                        onTemplateSelected: { template in
                            viewStore.send(.useRecommendedTemplate(template))
                        }
                    )
                }
            }
            .sheet(isPresented: .init(
                get: { viewStore.isEditing || viewStore.isCreating },
                set: { if !$0 { viewStore.send(.closeEditor) } }
            )) {
                TemplateEditorView(
                    template: viewStore.selectedTemplate,
                    isCreating: viewStore.isCreating,
                    onSave: { template in
                        viewStore.send(.templateSaved(template))
                    },
                    onCancel: {
                        viewStore.send(.closeEditor)
                    }
                )
            }
            .alert("Error", isPresented: .init(
                get: { viewStore.error != nil },
                set: { if !$0 { viewStore.error = nil } }
            )) {
                Text(viewStore.error ?? "")
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}

private struct TemplateRow: View {
    let template: TreatmentTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.headline)
            Text(template.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if template.isCustom {
                Text("Custom Template")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    let mode: TemplateListView.DocumentPickerMode
    let store: StoreOf<TemplateList>
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch mode {
        case .import:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.json],
                asCopy: true
            )
        case .export:
            picker = UIDocumentPickerViewController(
                forExporting: [],
                asCopy: true
            )
        }
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let store: StoreOf<TemplateList>
        
        init(store: StoreOf<TemplateList>) {
            self.store = store
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            Task {
                do {
                    let templates = try await ViewStore(store).templateManager.importTemplates(from: url)
                    await ViewStore(store).send(.templatesImported(templates))
                } catch {
                    await ViewStore(store).send(.errorOccurred(error.localizedDescription))
                }
            }
        }
    }
}
