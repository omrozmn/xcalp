import SwiftUI

struct AnglePreferencesView: View {
    @Binding var angles: TreatmentTemplate.AnglePreferences
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Text("Crown Angle: \(Int(angles.crown))°")
                    Slider(value: $angles.crown, in: 0...90)
                }
                
                VStack(alignment: .leading) {
                    Text("Hairline Angle: \(Int(angles.hairline))°")
                    Slider(value: $angles.hairline, in: 0...90)
                }
                
                VStack(alignment: .leading) {
                    Text("Temporal Angle: \(Int(angles.temporal))°")
                    Slider(value: $angles.temporal, in: 0...90)
                }
            } header: {
                Text("Angle Configuration")
            } footer: {
                Text("Angles are measured in degrees relative to the scalp surface")
            }
        }
        .navigationTitle("Angle Preferences")
    }
}
