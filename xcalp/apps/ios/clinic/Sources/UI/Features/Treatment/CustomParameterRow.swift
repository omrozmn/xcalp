import SwiftUI

struct CustomParameterRow: View {
    let parameter: TreatmentTemplate.Parameter
    let onUpdate: (TreatmentTemplate.Parameter) -> Void
    let onDelete: () -> Void
    
    @State private var value: String = ""
    @State private var showingEditor = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(parameter.name)
                        .xcalpText(.h3)
                    if let description = parameter.description {
                        Text(description)
                            .xcalpText(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit", action: { showingEditor = true })
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(BrandConstants.Colors.metallicGray)
                }
            }
            
            parameterInput
                .disabled(!parameter.isRequired && value.isEmpty)
        }
        .sheet(isPresented: $showingEditor) {
            ParameterValueEditorView(parameter: parameter) { updatedParameter in
                onUpdate(updatedParameter)
            }
        }
    }
    
    @ViewBuilder
    private var parameterInput: some View {
        switch parameter.type {
        case .number, .measurement, .density:
            numberInput
        case .direction:
            directionInput
        case .boolean:
            Toggle(parameter.name, isOn: Binding(
                get: { value == "true" },
                set: { value = $0 ? "true" : "false" }
            ))
        case .selection:
            if let options = parameter.range?.options {
                Picker(parameter.name, selection: $value) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
        case .text:
            TextField(parameter.name, text: $value)
        }
    }
    
    private var numberInput: some View {
        HStack {
            TextField(
                parameter.name,
                text: $value,
                prompt: Text(parameter.range?.unit ?? "")
            )
            .keyboardType(.decimalPad)
            
            if let unit = parameter.range?.unit {
                Text(unit)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var directionInput: some View {
        HStack {
            TextField("Direction", text: $value)
                .keyboardType(.decimalPad)
            Text("°")
                .foregroundColor(.secondary)
        }
    }
}
