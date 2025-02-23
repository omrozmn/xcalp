import SwiftUI

struct ParameterCreatorView: View {
    let onSave: (TreatmentTemplate.Parameter) -> Void
    let onCancel: () -> Void
    
    @State private var name = ""
    @State private var description = ""
    @State private var type: TreatmentTemplate.Parameter.ParameterType = .number
    @State private var isRequired = false
    @State private var hasRange = false
    @State private var minimum: String = ""
    @State private var maximum: String = ""
    @State private var step: String = ""
    @State private var unit: String = ""
    @State private var options: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Name", text: $name)
                    TextEditor(text: $description)
                        .frame(height: 100)
                    Toggle("Required", isOn: $isRequired)
                }
                
                Section(header: Text("Parameter Type")) {
                    Picker("Type", selection: $type) {
                        Text("Number").tag(TreatmentTemplate.Parameter.ParameterType.number)
                        Text("Text").tag(TreatmentTemplate.Parameter.ParameterType.text)
                        Text("Boolean").tag(TreatmentTemplate.Parameter.ParameterType.boolean)
                        Text("Selection").tag(TreatmentTemplate.Parameter.ParameterType.selection)
                        Text("Measurement").tag(TreatmentTemplate.Parameter.ParameterType.measurement)
                        Text("Density").tag(TreatmentTemplate.Parameter.ParameterType.density)
                        Text("Direction").tag(TreatmentTemplate.Parameter.ParameterType.direction)
                    }
                }
                
                if type != .boolean && type != .text {
                    Section(header: Text("Range Configuration")) {
                        Toggle("Has Range", isOn: $hasRange)
                        
                        if hasRange {
                            switch type {
                            case .number, .measurement, .density:
                                TextField("Minimum Value", text: $minimum)
                                    .keyboardType(.decimalPad)
                                TextField("Maximum Value", text: $maximum)
                                    .keyboardType(.decimalPad)
                                TextField("Step Value", text: $step)
                                    .keyboardType(.decimalPad)
                                TextField("Unit", text: $unit)
                                
                            case .selection:
                                TextField("Options (comma separated)", text: $options)
                                
                            case .direction:
                                Text("Direction range is fixed (0-360 degrees)")
                                
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Parameter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parameter = TreatmentTemplate.Parameter(
                            id: UUID(),
                            name: name,
                            type: type,
                            value: nil,
                            range: hasRange ? createRange() : nil,
                            isRequired: isRequired,
                            description: description.isEmpty ? nil : description
                        )
                        onSave(parameter)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        (!hasRange || isRangeValid)
    }
    
    private var isRangeValid: Bool {
        switch type {
        case .number, .measurement, .density:
            guard hasRange else { return true }
            guard let min = Double(minimum),
                  let max = Double(maximum),
                  let stepValue = Double(step)
            else { return false }
            return min < max && stepValue > 0
            
        case .selection:
            guard hasRange else { return true }
            let optionsList = options.split(separator: ",").map(String.init)
            return optionsList.count >= 2
            
        case .direction:
            return true
            
        case .text, .boolean:
            return true
        }
    }
    
    private func createRange() -> TreatmentTemplate.Parameter.ParameterRange {
        switch type {
        case .number, .measurement, .density:
            return .init(
                minimum: Double(minimum),
                maximum: Double(maximum),
                step: Double(step),
                options: nil,
                unit: unit.isEmpty ? nil : unit
            )
            
        case .selection:
            let optionsList = options.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            return .init(
                minimum: nil,
                maximum: nil,
                step: nil,
                options: optionsList,
                unit: nil
            )
            
        case .direction:
            return .init(
                minimum: 0,
                maximum: 360,
                step: 1,
                options: nil,
                unit: "degrees"
            )
            
        case .text, .boolean:
            return .init(
                minimum: nil,
                maximum: nil,
                step: nil,
                options: nil,
                unit: nil
            )
        }
    }
}