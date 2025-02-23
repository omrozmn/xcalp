import SwiftUI
import ComposableArchitecture

struct ValidationSystem {
    struct ValidationRule {
        let check: () -> Bool
        let message: String
        let severity: Severity
        
        enum Severity {
            case warning
            case error
        }
    }
    
    static func validateTreatment(_ treatment: TreatmentFeature.State.Treatment) -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Template Validation
        if treatment.appliedTemplate == nil {
            results.append(ValidationResult(
                message: "No template selected",
                severity: .error,
                area: .template
            ))
        }
        
        // Parameters Validation
        if let template = treatment.appliedTemplate {
            for parameter in template.parameters {
                if parameter.value == nil {
                    results.append(ValidationResult(
                        message: "Parameter '\(parameter.name)' has no value",
                        severity: .error,
                        area: .parameters
                    ))
                } else if let range = parameter.range,
                          let value = Double(parameter.value ?? ""),
                          let min = range.minimum,
                          let max = range.maximum,
                          value < min || value > max {
                    results.append(ValidationResult(
                        message: "Parameter '\(parameter.name)' value is out of range",
                        severity: .error,
                        area: .parameters
                    ))
                }
            }
        }
        
        // Regions Validation
        if treatment.regions.isEmpty {
            results.append(ValidationResult(
                message: "No regions defined",
                severity: .error,
                area: .regions
            ))
        }
        
        for region in treatment.regions {
            if region.graftCount == 0 {
                results.append(ValidationResult(
                    message: "Region '\(region.name)' has no grafts",
                    severity: .error,
                    area: .regions
                ))
            }
            
            if region.density < 10 {
                results.append(ValidationResult(
                    message: "Region '\(region.name)' has very low density",
                    severity: .warning,
                    area: .regions
                ))
            } else if region.density > 50 {
                results.append(ValidationResult(
                    message: "Region '\(region.name)' has very high density",
                    severity: .warning,
                    area: .regions
                ))
            }
            
            if region.environmentalFactors.isEmpty {
                results.append(ValidationResult(
                    message: "Region '\(region.name)' has no environmental factors",
                    severity: .warning,
                    area: .environmental
                ))
            }
        }
        
        return results
    }
    
    struct ValidationResult: Identifiable {
        let id = UUID()
        let message: String
        let severity: ValidationRule.Severity
        let area: ValidationArea
        
        enum ValidationArea {
            case template
            case parameters
            case regions
            case environmental
            
            var icon: String {
                switch self {
                case .template: return "doc.text"
                case .parameters: return "slider.horizontal.3"
                case .regions: return "circle.grid.cross"
                case .environmental: return "leaf"
                }
            }
        }
    }
}

struct ValidationFeedbackView: View {
    let results: [ValidationSystem.ValidationResult]
    let onFix: (ValidationSystem.ValidationResult) -> Void
    
    private var errorResults: [ValidationSystem.ValidationResult] {
        results.filter { $0.severity == .error }
    }
    
    private var warningResults: [ValidationSystem.ValidationResult] {
        results.filter { $0.severity == .warning }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Medical Alert Banner
            if !errorResults.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Action Required")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(errorResults.count) issue\(errorResults.count == 1 ? "" : "s") need\(errorResults.count == 1 ? "s" : "") to be resolved")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandConstants.Colors.errorRed)
                .cornerRadius(BrandConstants.Layout.cornerRadius)
            }
            
            // Validation Groups
            if !errorResults.isEmpty {
                ValidationGroup(
                    title: "Required Actions",
                    results: errorResults,
                    onFix: onFix
                )
            }
            
            if !warningResults.isEmpty {
                ValidationGroup(
                    title: "Recommendations",
                    results: warningResults,
                    onFix: onFix
                )
            }
        }
        .animation(.easeInOut, value: results)
    }
}

private struct ValidationGroup: View {
    let title: String
    let results: [ValidationSystem.ValidationResult]
    let onFix: (ValidationSystem.ValidationResult) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .xcalpText(.h3)
            
            VStack(spacing: 12) {
                ForEach(results) { result in
                    ValidationResultRow(result: result, onFix: onFix)
                }
            }
        }
    }
}

private struct ValidationResultRow: View {
    let result: ValidationSystem.ValidationResult
    let onFix: (ValidationSystem.ValidationResult) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 32, height: 32)
                
                Image(systemName: result.severity == .error ? "xmark" : "exclamationmark")
                    .foregroundColor(.white)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.message)
                    .xcalpText(.body)
                
                HStack(spacing: 8) {
                    Label {
                        Text(areaDescription)
                            .xcalpText(.caption)
                    } icon: {
                        Image(systemName: result.area.icon)
                            .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    }
                    
                    if let recommendation = getRecommendation() {
                        Text("•")
                            .xcalpText(.caption)
                            .foregroundColor(BrandConstants.Colors.metallicGray)
                        Text(recommendation)
                            .xcalpText(.caption)
                            .foregroundColor(BrandConstants.Colors.metallicGray)
                    }
                }
            }
            
            Spacer()
            
            // Action Button
            Button {
                onFix(result)
            } label: {
                Text(actionText)
                    .xcalpText(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(actionBackground)
                    .foregroundColor(.white)
                    .cornerRadius(BrandConstants.Layout.cornerRadius)
            }
        }
        .padding()
        .background(rowBackground)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
    
    private var iconBackground: Color {
        result.severity == .error ?
            BrandConstants.Colors.errorRed :
            BrandConstants.Colors.warningYellow
    }
    
    private var rowBackground: Color {
        (result.severity == .error ?
            BrandConstants.Colors.errorRed :
            BrandConstants.Colors.warningYellow)
            .opacity(0.1)
    }
    
    private var actionBackground: Color {
        result.severity == .error ?
            BrandConstants.Colors.errorRed :
            BrandConstants.Colors.vibrantBlue
    }
    
    private var actionText: String {
        result.severity == .error ? "Fix Now" : "Review"
    }
    
    private var areaDescription: String {
        switch result.area {
        case .template: return "Template Selection"
        case .parameters: return "Parameter Values"
        case .regions: return "Region Definition"
        case .environmental: return "Environmental Factors"
        }
    }
    
    private func getRecommendation() -> String? {
        switch result.area {
        case .template:
            return "Choose a suitable template"
        case .parameters:
            if result.message.contains("out of range") {
                return "Adjust within recommended range"
            } else {
                return "Set required parameter value"
            }
        case .regions:
            if result.message.contains("density") {
                return "Review density settings"
            } else {
                return "Define treatment regions"
            }
        case .environmental:
            return "Consider environmental impacts"
        }
    }
}

private extension ValidationSystem.ValidationResult.ValidationArea {
    var description: String {
        switch self {
        case .template: return "Template Selection"
        case .parameters: return "Parameter Values"
        case .regions: return "Region Definition"
        case .environmental: return "Environmental Factors"
        }
    }
}