import SwiftUI
import ComposableArchitecture

struct ParameterCustomizationView: View {
    let template: TreatmentTemplate
    let onChange: ([TemplateParameter]) -> Void
    @State private var parameters: [TemplateParameter]
    
    init(template: TreatmentTemplate, onChange: @escaping ([TemplateParameter]) -> Void) {
        self.template = template
        self.onChange = onChange
        self._parameters = State(initialValue: template.parameters)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Parameter Groups
            ForEach(ParameterType.allCases, id: \.self) { type in
                let typeParameters = parameters.filter { $0.type == type }
                if !typeParameters.isEmpty {
                    ParameterGroup(
                        type: type,
                        parameters: typeParameters,
                        onChange: { updatedParameter in
                            if let index = parameters.firstIndex(where: { $0.id == updatedParameter.id }) {
                                parameters[index] = updatedParameter
                                onChange(parameters)
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct ParameterGroup: View {
    let type: ParameterType
    let parameters: [TemplateParameter]
    let onChange: (TemplateParameter) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text(type.displayName)
                        .xcalpText(.h2)
                } icon: {
                    Image(systemName: type.iconName)
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                }
                
                Spacer()
                
                Text("\(parameters.count)")
                    .xcalpText(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandConstants.Colors.lightSilver)
                    .cornerRadius(BrandConstants.Layout.cornerRadius)
            }
            
            ForEach(parameters) { parameter in
                ParameterEditor(parameter: parameter) { value in
                    var updated = parameter
                    updated.value = value
                    onChange(updated)
                }
            }
        }
        .xcalpCard()
    }
}

private struct ParameterEditor: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(parameter.name)
                    .xcalpText(.h3)
                Spacer()
                if let range = parameter.range {
                    RangeIndicator(range: range, currentValue: parameter.value)
                }
            }
            
            switch parameter.type {
            case .number, .measurement, .density:
                NumericParameterInput(
                    parameter: parameter,
                    onValueChanged: onValueChanged
                )
                
            case .text:
                TextParameterInput(
                    parameter: parameter,
                    onValueChanged: onValueChanged
                )
                
            case .boolean:
                BooleanParameterInput(
                    parameter: parameter,
                    onValueChanged: onValueChanged
                )
                
            case .selection:
                SelectionParameterInput(
                    parameter: parameter,
                    onValueChanged: onValueChanged
                )
                
            case .direction:
                DirectionParameterInput(
                    parameter: parameter,
                    onValueChanged: onValueChanged
                )
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
}

private struct NumericParameterInput: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    @State private var value: String
    @FocusState private var isFocused: Bool
    
    init(parameter: TemplateParameter, onValueChanged: @escaping (String) -> Void) {
        self.parameter = parameter
        self.onValueChanged = onValueChanged
        self._value = State(initialValue: parameter.value ?? parameter.defaultValue)
    }
    
    var body: some View {
        HStack {
            TextField("Value", text: $value) { isEditing in
                isFocused = isEditing
            } onCommit: {
                validateAndUpdate()
            }
            .xcalpTextField()
            .keyboardType(.decimalPad)
            .focused($isFocused)
            
            switch parameter.type {
            case .measurement:
                Text("mm")
                    .xcalpText(.caption)
            case .density:
                Text("grafts/cm²")
                    .xcalpText(.caption)
            default:
                EmptyView()
            }
        }
        .onChange(of: value) { newValue in
            if !isFocused {
                validateAndUpdate()
            }
        }
    }
    
    private func validateAndUpdate() {
        guard let doubleValue = Double(value) else { return }
        if let range = parameter.range {
            if let min = range.minimum, doubleValue < min {
                value = String(min)
            }
            if let max = range.maximum, doubleValue > max {
                value = String(max)
            }
        }
        onValueChanged(value)
    }
}

private struct TextParameterInput: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    @State private var value: String
    
    init(parameter: TemplateParameter, onValueChanged: @escaping (String) -> Void) {
        self.parameter = parameter
        self.onValueChanged = onValueChanged
        self._value = State(initialValue: parameter.value ?? parameter.defaultValue)
    }
    
    var body: some View {
        TextField("Value", text: $value)
            .xcalpTextField()
            .onChange(of: value) { newValue in
                onValueChanged(newValue)
            }
    }
}

private struct BooleanParameterInput: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    @State private var isEnabled: Bool
    
    init(parameter: TemplateParameter, onValueChanged: @escaping (String) -> Void) {
        self.parameter = parameter
        self.onValueChanged = onValueChanged
        self._isEnabled = State(initialValue: (parameter.value ?? parameter.defaultValue) == "true")
    }
    
    var body: some View {
        Toggle("Enabled", isOn: $isEnabled)
            .tint(BrandConstants.Colors.vibrantBlue)
            .onChange(of: isEnabled) { newValue in
                onValueChanged(newValue ? "true" : "false")
            }
    }
}

private struct SelectionParameterInput: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    @State private var selectedOption: String
    
    init(parameter: TemplateParameter, onValueChanged: @escaping (String) -> Void) {
        self.parameter = parameter
        self.onValueChanged = onValueChanged
        let initialValue = parameter.value ?? parameter.defaultValue
        self._selectedOption = State(initialValue: initialValue)
    }
    
    var body: some View {
        if let options = parameter.range?.options {
            Picker("Value", selection: $selectedOption) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .xcalpTextField()
            .onChange(of: selectedOption) { newValue in
                onValueChanged(newValue)
            }
        }
    }
}

private struct DirectionParameterInput: View {
    let parameter: TemplateParameter
    let onValueChanged: (String) -> Void
    @State private var angle: Double
    
    init(parameter: TemplateParameter, onValueChanged: @escaping (String) -> Void) {
        self.parameter = parameter
        self.onValueChanged = onValueChanged
        self._angle = State(initialValue: Double(parameter.value ?? parameter.defaultValue) ?? 0)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(BrandConstants.Colors.lightSilver, lineWidth: 2)
                    .frame(width: 100, height: 100)
                
                Rectangle()
                    .fill(BrandConstants.Colors.vibrantBlue)
                    .frame(width: 2, height: 50)
                    .offset(y: -25)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 100, height: 100)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: 50, y: 50)
                        let point = value.location
                        angle = Double(atan2(point.y - center.y, point.x - center.x)) * 180 / .pi + 90
                        onValueChanged(String(format: "%.0f", angle))
                    }
            )
            
            HStack {
                TextField("Angle", value: $angle, formatter: NumberFormatter())
                    .xcalpTextField()
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                
                Text("degrees")
                    .xcalpText(.caption)
            }
        }
    }
}

private struct RangeIndicator: View {
    let range: ParameterRange
    let currentValue: String?
    
    var body: some View {
        HStack(spacing: 4) {
            if let min = range.minimum {
                Text(String(format: "%.1f", min))
                    .xcalpText(.small)
            }
            
            if range.minimum != nil || range.maximum != nil {
                Text("-")
                    .xcalpText(.small)
            }
            
            if let max = range.maximum {
                Text(String(format: "%.1f", max))
                    .xcalpText(.small)
            }
        }
        .foregroundColor(isValueInRange ? BrandConstants.Colors.metallicGray : BrandConstants.Colors.errorRed)
    }
    
    private var isValueInRange: Bool {
        guard let value = Double(currentValue ?? ""),
              let range = range.minimum...range.maximum else { return true }
        return range.contains(value)
    }
}

private extension ParameterType {
    var displayName: String {
        switch self {
        case .number: return "Numeric Values"
        case .text: return "Text Values"
        case .boolean: return "Toggle Options"
        case .selection: return "Selection Options"
        case .measurement: return "Measurements"
        case .density: return "Density Values"
        case .direction: return "Direction Values"
        }
    }
    
    var iconName: String {
        switch self {
        case .number: return "number"
        case .text: return "text.alignleft"
        case .boolean: return "switch.2"
        case .selection: return "list.bullet"
        case .measurement: return "ruler"
        case .density: return "chart.bar.fill"
        case .direction: return "arrow.up.right"
        }
    }
}