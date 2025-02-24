import SwiftUI

struct MarginEditorView: View {
    @Binding var margins: TreatmentTemplate.Margins
    
    var body: some View {
        Form {
            HStack {
                Text("Anterior")
                Spacer()
                TextField("mm", value: $margins.anterior, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Posterior")
                Spacer()
                TextField("mm", value: $margins.posterior, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack {
                Text("Lateral")
                Spacer()
                TextField("mm", value: $margins.lateral, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
        .navigationTitle("Safety Margins")
    }
}
