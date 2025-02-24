import SwiftUI

struct CustomParameterEditorView: View {
    let onSave: (TreatmentTemplate.Parameter) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = TreatmentTemplate.Parameter.ParameterType.number
    @State private var description = ""
    @State private var isRequired = true
    @State private var minimum: Double?
    @State private var maximum: Double?
    @State private var step: Double?
    @State private var options: [String] = []
    @State private var unit: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        Text("Number").tag(TreatmentTemplate.Parameter.ParameterType.number)
                        Text("Text").tag(TreatmentTemplate.Parameter.ParameterType.text)
                        Text("Boolean").tag(TreatmentTemplate.Parameter.ParameterType.boolean)
                        Text("Selection").tag(TreatmentTemplate.Parameter.ParameterType.selection)
                        Text("Measurement").tag(TreatmentTemplate.Parameter.ParameterType.measurement)
                        Text("Density").tag(TreatmentTemplate.Parameter.ParameterType.density)
                        Text("Direction").tag(TreatmentTemplate.Parameter.ParameterType.direction)
                    }
                    TextEditor(text: $description)
                        .frame(height: 100)
                    Toggle("Required", isOn: $isRequired)
                }
                
                if type == .number || type == .measurement || type == .density {
                    Section(header: Text("Range")) {
                        HStack {
                            Text("Minimum")
                            Spacer()
                            TextField("Optional", value: $minimum, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("Maximum")
                            Spacer()
                            TextField("Optional", value: $maximum, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("Step")
                            Spacer()
                            TextField("Optional", value: $step, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                        }
                    }
                }
                
                if type == .measurement || type == .density {
                    Section(header: Text("Unit")) {
                        TextField("Unit (e.g., mm, cm²)", text: Binding(
                            get: { unit ?? "" },
                            set: { unit = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }
                
                if type == .selection {
                    Section(header: Text("Options")) {
                        ForEach(options.indices, id: \.self) { index in
                            TextField("Option \(index + 1)", text: $options[index])
                        }
                        Button("Add Option") {
                            options.append("")
                        }
                    }
                }
            }
            .navigationTitle("Custom Parameter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        !description.isEmpty &&
        (type != .selection || !options.isEmpty) &&
        (type != .measurement && type != .density || unit != nil)
    }
    
    private func save() {
        let range = TreatmentTemplate.Parameter.ParameterRange(
            minimum: minimum,
            maximum: maximum,
            step: step,
            options: type == .selection ? options : nil,
            unit: unit
        )
        
        let parameter = TreatmentTemplate.Parameter(
            id: UUID(),
            name: name,
            type: type,
            value: nil,
            range: range,
            isRequired: isRequired,
            description: description
        )
        
        onSave(parameter)
        dismiss()
    }
}
