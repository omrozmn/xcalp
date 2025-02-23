import SwiftUI
import ComposableArchitecture

struct TreatmentStepView: View {
    enum Step: Int, CaseIterable {
        case selectTemplate
        case customizeParameters
        case defineRegions
        case environmentalFactors
        case review
        
        var title: String {
            switch self {
            case .selectTemplate: return "Select Template"
            case .customizeParameters: return "Customize Parameters"
            case .defineRegions: return "Define Regions"
            case .environmentalFactors: return "Environmental Factors"
            case .review: return "Review"
            }
        }
        
        var systemImage: String {
            switch self {
            case .selectTemplate: return "doc.text.magnifyingglass"
            case .customizeParameters: return "slider.horizontal.3"
            case .defineRegions: return "circle.grid.cross"
            case .environmentalFactors: return "sun.max"
            case .review: return "checkmark.circle"
            }
        }
    }
    
    let store: StoreOf<TreatmentFeature>
    @State private var currentStep: Step = .selectTemplate
    
    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 0) {
                // Medical-Grade Progress Header
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .shadow(
                            color: BrandConstants.Colors.darkGray.opacity(0.05),
                            radius: 8,
                            x: 0,
                            y: 2
                        )
                    
                    VStack(spacing: 16) {
                        // Treatment Info
                        if let patient = viewStore.patient {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(patient.name)
                                        .xcalpText(.h3)
                                    Text("Treatment Plan")
                                        .xcalpText(.caption)
                                }
                                Spacer()
                                Text(Date().formatted(date: .abbreviated, time: .omitted))
                                    .xcalpText(.caption)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Progress Steps
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(Step.allCases, id: \.rawValue) { step in
                                    StepIndicator(
                                        step: step,
                                        currentStep: currentStep,
                                        validationResults: viewStore.validationResults
                                    )
                                    if step != .review {
                                        StepConnector(
                                            isActive: step.rawValue < currentStep.rawValue,
                                            hasWarning: hasWarning(for: step, results: viewStore.validationResults)
                                        )
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .padding(.vertical)
                }
                .frame(height: 120)
                
                // Step Content with Medical Context
                ScrollView {
                    VStack(spacing: 20) {
                        // Current Step Status
                        StepStatusCard(
                            step: currentStep,
                            validationResults: viewStore.validationResults
                        )
                        
                        // Step Content
                        switch currentStep {
                        case .selectTemplate:
                            TemplateSelectionView(store: store)
                        case .customizeParameters:
                            if let treatment = viewStore.currentTreatment,
                               let template = treatment.appliedTemplate {
                                ParameterCustomizationView(
                                    template: template,
                                    onChange: { parameters in
                                        viewStore.send(.updateParameters(parameters))
                                    }
                                )
                            }
                        case .defineRegions:
                            if let treatment = viewStore.currentTreatment {
                                RegionsEditor(
                                    regions: treatment.regions,
                                    onChange: { regions in
                                        viewStore.send(.updateRegions(regions))
                                    }
                                )
                            }
                        case .environmentalFactors:
                            if let treatment = viewStore.currentTreatment {
                                EnvironmentalFactorsView(
                                    regions: treatment.regions,
                                    onChange: { regions in
                                        viewStore.send(.updateRegions(regions))
                                    }
                                )
                            }
                        case .review:
                            if let treatment = viewStore.currentTreatment {
                                TreatmentReviewView(
                                    treatment: treatment,
                                    validationResults: viewStore.validationResults
                                )
                            }
                        }
                        
                        // Inline Validation Feedback
                        if !viewStore.validationResults.isEmpty {
                            ValidationFeedbackView(
                                results: viewStore.validationResults.filter { result in
                                    result.area.matchesStep(currentStep)
                                },
                                onFix: { result in
                                    viewStore.send(.fixValidationIssue(result))
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                // Medical-Grade Action Bar
                VStack(spacing: 12) {
                    // Progress Summary
                    if let treatment = viewStore.currentTreatment {
                        HStack {
                            ProgressSummary(
                                treatment: treatment,
                                validationResults: viewStore.validationResults
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Navigation
                    HStack {
                        if currentStep != .selectTemplate {
                            Button("Back") {
                                withAnimation {
                                    currentStep = Step(rawValue: currentStep.rawValue - 1) ?? .selectTemplate
                                }
                            }
                            .buttonStyle(XcalpButton(style: .secondary))
                        }
                        
                        if currentStep != .review {
                            Button("Next") {
                                withAnimation {
                                    currentStep = Step(rawValue: currentStep.rawValue + 1) ?? .review
                                }
                            }
                            .buttonStyle(XcalpButton(style: .primary))
                        } else {
                            Button("Finalize Treatment") {
                                viewStore.send(.saveTreatment)
                            }
                            .buttonStyle(XcalpButton(style: .primary))
                            .disabled(!viewStore.validationResults.filter { $0.severity == .error }.isEmpty)
                        }
                    }
                    .padding()
                }
                .background(Color.white)
                .shadow(
                    color: BrandConstants.Colors.darkGray.opacity(0.1),
                    radius: 10,
                    y: -2
                )
            }
            .background(BrandConstants.Colors.lightBackground)
            .navigationTitle(currentStep.title)
            .xcalpNavigationBar()
        }
    }
    
    private func hasWarning(for step: Step, results: [ValidationSystem.ValidationResult]) -> Bool {
        results.contains { result in
            result.area.matchesStep(step)
        }
    }
}

private struct StepIndicator: View {
    let step: TreatmentStepView.Step
    let currentStep: TreatmentStepView.Step
    let validationResults: [ValidationSystem.ValidationResult]
    
    private var isComplete: Bool {
        step.rawValue < currentStep.rawValue
    }
    
    private var isActive: Bool {
        step == currentStep
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                } else {
                    Image(systemName: step.systemImage)
                        .foregroundColor(isActive ? .white : BrandConstants.Colors.metallicGray)
                }
            }
            
            Text(step.title)
                .xcalpText(isActive ? .caption : .small)
                .foregroundColor(isActive ? BrandConstants.Colors.darkNavy : BrandConstants.Colors.metallicGray)
        }
        .frame(height: 80)
    }
    
    private var backgroundColor: Color {
        if isComplete {
            return BrandConstants.Colors.vibrantBlue
        } else if isActive {
            return BrandConstants.Colors.darkNavy
        } else {
            return BrandConstants.Colors.lightSilver
        }
    }
}

private struct StepConnector: View {
    let isActive: Bool
    let hasWarning: Bool
    
    var body: some View {
        Rectangle()
            .fill(connectorColor)
            .frame(width: 40, height: 2)
    }
    
    private var connectorColor: Color {
        if hasWarning {
            return BrandConstants.Colors.warningYellow
        } else if isActive {
            return BrandConstants.Colors.vibrantBlue
        } else {
            return BrandConstants.Colors.lightSilver
        }
    }
}

private struct EnvironmentalFactorsView: View {
    let regions: [TreatmentRegion]
    let onChange: ([TreatmentRegion]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Environmental Considerations")
                .xcalpText(.h2)
            
            ForEach(regions) { region in
                RegionEnvironmentCard(region: region)
            }
        }
        .xcalpCard()
    }
}

private struct RegionEnvironmentCard: View {
    let region: TreatmentRegion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(region.name)
                .xcalpText(.h3)
            
            ForEach(EnvironmentType.allCases, id: \.self) { type in
                HStack {
                    Label {
                        Text(type.rawValue.capitalized)
                            .xcalpText(.body)
                    } icon: {
                        Image(systemName: iconName(for: type))
                            .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    }
                    
                    Spacer()
                    
                    if let factor = region.environmentalFactors.first(where: { $0.type == type }) {
                        Text(String(format: "%.1f", factor.impact))
                            .xcalpText(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
    }
    
    private func iconName(for type: EnvironmentType) -> String {
        switch type {
        case .sunExposure: return "sun.max"
        case .humidity: return "humidity"
        case .temperature: return "thermometer"
        case .lifestyle: return "figure.walk"
        }
    }
}

private struct TreatmentReviewView: View {
    let treatment: TreatmentFeature.State.Treatment
    let validationResults: [ValidationSystem.ValidationResult]
    
    var body: some View {
        VStack(spacing: 20) {
            if let template = treatment.appliedTemplate {
                TemplateInfoCard(template: template)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Treatment Summary")
                    .xcalpText(.h2)
                
                VStack(alignment: .leading, spacing: 8) {
                    SummaryRow(
                        title: "Total Regions",
                        value: "\(treatment.regions.count)",
                        icon: "circle.grid.cross"
                    )
                    
                    SummaryRow(
                        title: "Total Grafts",
                        value: "\(treatment.regions.reduce(0) { $0 + $1.graftCount })",
                        icon: "number"
                    )
                    
                    SummaryRow(
                        title: "Average Density",
                        value: "\(Int(treatment.regions.reduce(0.0) { $0 + $1.density } / Double(treatment.regions.count))) grafts/cm²",
                        icon: "chart.bar.fill"
                    )
                }
            }
            .xcalpCard()
            
            if !treatment.notes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes")
                        .xcalpText(.h2)
                    
                    Text(treatment.notes)
                        .xcalpText(.body)
                }
                .xcalpCard()
            }
            
            // Validation Summary
            if !validationResults.isEmpty {
                ValidationFeedbackView(
                    results: validationResults,
                    onFix: { result in
                        // Handle fix action
                    }
                )
            }
        }
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Label {
                Text(title)
                    .xcalpText(.body)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(BrandConstants.Colors.vibrantBlue)
            }
            
            Spacer()
            
            Text(value)
                .xcalpText(.body)
        }
    }
}

private struct StepStatusCard: View {
    let step: TreatmentStepView.Step
    let validationResults: [ValidationSystem.ValidationResult]
    
    private var stepResults: [ValidationSystem.ValidationResult] {
        validationResults.filter { result in
            result.area.matchesStep(step)
        }
    }
    
    var body: some View {
        if !stepResults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: step.systemImage)
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    Text(step.title)
                        .xcalpText(.h3)
                    Spacer()
                    StatusBadge(results: stepResults)
                }
                
                Text(statusMessage)
                    .xcalpText(.body)
                
                if let tip = step.tip {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(BrandConstants.Colors.warningYellow)
                        Text(tip)
                            .xcalpText(.caption)
                    }
                    .padding()
                    .background(BrandConstants.Colors.warningYellow.opacity(0.1))
                    .cornerRadius(BrandConstants.Layout.cornerRadius)
                }
            }
            .padding()
            .background(statusBackground)
            .cornerRadius(BrandConstants.Layout.cornerRadius)
        }
    }
    
    private var statusMessage: String {
        if stepResults.contains(where: { $0.severity == .error }) {
            return "Please address the following issues to proceed"
        } else if !stepResults.isEmpty {
            return "Review recommendations before proceeding"
        } else {
            return "All requirements met"
        }
    }
    
    private var statusBackground: Color {
        if stepResults.contains(where: { $0.severity == .error }) {
            return BrandConstants.Colors.errorRed.opacity(0.1)
        } else if !stepResults.isEmpty {
            return BrandConstants.Colors.warningYellow.opacity(0.1)
        } else {
            return BrandConstants.Colors.successGreen.opacity(0.1)
        }
    }
}

private struct StatusBadge: View {
    let results: [ValidationSystem.ValidationResult]
    
    var body: some View {
        HStack(spacing: 4) {
            if results.contains(where: { $0.severity == .error }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(BrandConstants.Colors.errorRed)
                Text("Action Required")
                    .xcalpText(.caption)
                    .foregroundColor(BrandConstants.Colors.errorRed)
            } else if !results.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(BrandConstants.Colors.warningYellow)
                Text("Review Recommended")
                    .xcalpText(.caption)
                    .foregroundColor(BrandConstants.Colors.warningYellow)
            } else {