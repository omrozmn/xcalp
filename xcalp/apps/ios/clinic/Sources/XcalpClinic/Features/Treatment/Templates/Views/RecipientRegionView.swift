import SwiftUI

struct RecipientRegionView: View {
    @Binding var recipient: TreatmentTemplate.RecipientRegion
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Target Hairline Position")
                    Spacer()
                    TextField("mm", value: $recipient.targetHairlinePosition, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                
                VStack(alignment: .leading) {
                    Text("Natural Angle Variation: ±\(Int(recipient.naturalAngleVariation))°")
                    Slider(value: $recipient.naturalAngleVariation, in: 0...15)
                }
                
                HStack {
                    Text("Density Gradient")
                    Spacer()
                    TextField("grafts/cm²", value: $recipient.densityGradient, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("These settings control the natural appearance of the transplanted hair")
            }
        }
        .navigationTitle("Recipient Region")
    }
}
