import SwiftUI

struct TreatmentGuidanceSystem: View {
    @Binding var currentStep: Int
    let totalSteps: Int
    let onComplete: () -> Void
    
    struct GuidanceStep {
        let title: String
        let description: String
        let image: String
        let tip: String?
    }
    
    private let steps: [GuidanceStep] = [
        GuidanceStep(
            title: "Select a Template",
            description: "Choose from our collection of professional treatment templates or create your own custom template.",
            image: "doc.text.magnifyingglass",
            tip: "Use filters to quickly find templates matching your needs"
        ),
        GuidanceStep(
            title: "Customize Parameters",
            description: "Adjust treatment parameters based on patient needs and conditions.",
            image: "slider.horizontal.3",
            tip: "Parameters with a range indicator show recommended minimum and maximum values"
        ),
        GuidanceStep(
            title: "Define Treatment Regions",
            description: "Specify the regions for treatment, including graft density and direction.",
            image: "circle.grid.cross",
            tip: "Use the 3D viewer to precisely define region boundaries"
        ),
        GuidanceStep(
            title: "Environmental Factors",
            description: "Consider environmental impacts on treatment effectiveness.",
            image: "leaf",
            tip: "Account for patient lifestyle and environmental exposure"
        ),
        GuidanceStep(
            title: "Review and Validate",
            description: "Review all aspects of the treatment plan and validate for completeness.",
            image: "checkmark.circle",
            tip: "Address any warnings or errors before finalizing"
        )
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress Indicator
            HStack {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Rectangle()
                        .fill(step <= currentStep ? BrandConstants.Colors.vibrantBlue : BrandConstants.Colors.lightSilver)
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }
            
            if currentStep < steps.count {
                let step = steps[currentStep]
                
                // Step Content
                VStack(spacing: 16) {
                    Image(systemName: step.image)
                        .font(.system(size: 40))
                        .foregroundColor(BrandConstants.Colors.vibrantBlue)
                    
                    Text(step.title)
                        .xcalpText(.h2)
                    
                    Text(step.description)
                        .xcalpText(.body)
                        .multilineTextAlignment(.center)
                    
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
                
                // Navigation
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(XcalpButton(style: .secondary))
                    }
                    
                    if currentStep < totalSteps - 1 {
                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(XcalpButton(style: .primary))
                    } else {
                        Button("Get Started") {
                            onComplete()
                        }
                        .buttonStyle(XcalpButton(style: .primary))
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(BrandConstants.Layout.cornerRadius)
        .shadow(
            color: BrandConstants.Colors.darkGray.opacity(0.1),
            radius: 10,
            x: 0,
            y: 2
        )
    }
}