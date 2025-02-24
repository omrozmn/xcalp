import ComposableArchitecture
import SwiftUI

public struct AnalysisView: View {
    let store: StoreOf<AnalysisFeature>
    
    public init(store: StoreOf<AnalysisFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationView {
                VStack(spacing: 20) {
                    // Analysis Type Picker
                    Picker("Analysis Type", selection: viewStore.binding(
                        get: { $0.selectedAnalysisType },
                        send: AnalysisFeature.Action.selectAnalysisType
                    )) {
                        Text("Select Type").tag(Optional<AnalysisFeature.AnalysisType>.none)
                        ForEach(AnalysisFeature.AnalysisType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if viewStore.isAnalyzing {
                        VStack {
                            ProgressView(value: viewStore.progress) {
                                Text("Analyzing...")
                                    .xcalpText(.caption)
                            }
                            Text("\(Int(viewStore.progress * 100))%")
                                .xcalpText(.caption)
                        }
                        .padding()
                    }
                    
                    // Results List
                    List {
                        ForEach(viewStore.results) { result in
                            AnalysisResultRow(result: result)
                        }
                    }
                    .listStyle(.plain)
                    
                    // Start Analysis Button
                    if !viewStore.isAnalyzing {
                        XcalpButton(
                            title: "Start Analysis",
                            isLoading: viewStore.isAnalyzing
                        ) {
                            viewStore.send(.startAnalysis)
                        }
                        .padding()
                        .disabled(viewStore.selectedAnalysisType == nil)
                    }
                }
                .navigationTitle("Analysis")
                .alert(
                    "Error",
                    isPresented: viewStore.binding(
                        get: { $0.errorMessage != nil },
                        send: { _ in .setError(nil) }
                    ),
                    presenting: viewStore.errorMessage
                ) { _ in
                    Button("OK") { viewStore.send(.setError(nil)) }
                } message: { message in
                    Text(message)
                }
            }
        }
    }
}

private struct AnalysisResultRow: View {
    let result: AnalysisFeature.AnalysisResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.type.rawValue)
                .xcalpText(.h3)
            
            Text(result.date.formatted(date: .abbreviated, time: .shortened))
                .xcalpText(.caption)
            
            Text(result.summary)
                .xcalpText(.body)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}
