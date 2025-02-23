import SwiftUI
import ComposableArchitecture

public struct OfflineModeView: View {
    let store: StoreOf<ProcessingFeature>
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 16) {
                // Offline Mode Toggle
                HStack {
                    Image(systemName: viewStore.offlineMode ? "wifi.slash" : "wifi")
                        .foregroundColor(viewStore.offlineMode ? .red : .green)
                    
                    Toggle("Offline Mode", isOn: viewStore.binding(
                        get: \.offlineMode,
                        send: { .toggleOfflineMode }
                    ))
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 2)
                
                // Queue Status
                if !viewStore.queuedOperations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Queued Operations")
                            .font(.headline)
                        
                        ForEach(viewStore.queuedOperations, id: \.id) { operation in
                            HStack {
                                Image(systemName: "doc.circle")
                                Text(operation.type.rawValue)
                                Spacer()
                                Text(operation.timestamp.formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Button {
                            viewStore.send(.syncWithServer)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Now")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewStore.isProcessing)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                }
                
                // Processing Status
                if viewStore.isProcessing {
                    VStack {
                        ProgressView(value: viewStore.progress) {
                            Text("Processing...")
                        }
                        
                        if let operation = viewStore.currentOperation {
                            Text("Processing \(operation.type.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                }
                
                // Error Display
                if let error = viewStore.error {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                        }
                        
                        Button("Dismiss") {
                            viewStore.send(.dismissError)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                }
            }
            .padding()
            .navigationTitle("Offline Mode")
            .alert(
                "Storage Warning",
                isPresented: viewStore.binding(
                    get: { $0.error is StorageError },
                    send: .dismissError
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                if case let .storageLimitExceeded(available) = viewStore.error as? StorageError {
                    Text("Storage space is running low. Available: \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file))")
                }
            }
        }
    }
}

// Preview provider for SwiftUI previews
struct OfflineModeView_Previews: PreviewProvider {
    static var previews: some View {
        OfflineModeView(
            store: Store(
                initialState: ProcessingFeature.State(),
                reducer: ProcessingFeature()
            )
        )
    }
}
