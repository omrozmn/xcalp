import SwiftUI

struct DonorRegionView: View {
    @Binding var donor: TreatmentTemplate.DonorRegion
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Safe Extraction Depth")
                    Spacer()
                    TextField("mm", value: $donor.safeExtractionDepth, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Maximum Graft Density")
                    Spacer()
                    TextField("grafts/cm²", value: $donor.maxGraftDensity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Text("Minimum Follicle Spacing")
                    Spacer()
                    TextField("mm", value: $donor.minimumFollicleSpacing, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("These parameters ensure safe and optimal graft extraction from donor areas")
            }
        }
        .navigationTitle("Donor Region")
    }
}