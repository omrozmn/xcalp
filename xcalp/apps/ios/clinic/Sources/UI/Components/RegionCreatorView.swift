import SwiftUI

struct RegionCreatorView: View {
    let onSave: (TreatmentRegion) -> Void
    let onCancel: () -> Void
    
    @State private var name = ""
    @State private var type: TreatmentRegion.RegionType = .recipient
    @State private var density = 40.0
    @State private var direction = 0.0
    @State private var spacing = 0.8
    @State private var maxDeviation = 15.0
    @State private var boundaries: [Point3D] = []
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Region Name", text: $name)
                    Picker("Region Type", selection: $type) {
                        Text("Recipient Area").tag(TreatmentRegion.RegionType.recipient)
                        Text("Donor Area").tag(TreatmentRegion.RegionType.donor)
                    }
                }
                
                Section(header: Text("Parameters")) {
                    VStack(alignment: .leading) {
                        Text("Density (grafts/cm²)")
                        Slider(value: $density, in: 20...60, step: 1) {
                            Text("Density")
                        } minimumValueLabel: {
                            Text("20")
                        } maximumValueLabel: {
                            Text("60")
                        }
                        Text("\(Int(density))")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Direction (degrees)")
                        Slider(value: $direction, in: 0...360, step: 1) {
                            Text("Direction")
                        } minimumValueLabel: {
                            Text("0°")
                        } maximumValueLabel: {
                            Text("360°")
                        }
                        Text("\(Int(direction))°")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Graft Spacing (mm)")
                        Slider(value: $spacing, in: 0.5...1.5, step: 0.1) {
                            Text("Spacing")
                        } minimumValueLabel: {
                            Text("0.5")
                        } maximumValueLabel: {
                            Text("1.5")
                        }
                        Text(String(format: "%.1f", spacing))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Maximum Deviation (degrees)")
                        Slider(value: $maxDeviation, in: 0...30, step: 1) {
                            Text("Maximum Deviation")
                        } minimumValueLabel: {
                            Text("0°")
                        } maximumValueLabel: {
                            Text("30°")
                        }
                        Text("\(Int(maxDeviation))°")
                    }
                }
                
                Section(header: Text("Region Boundaries")) {
                    if boundaries.isEmpty {
                        Text("Use the 3D viewer to define region boundaries")
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(boundaries.count) points defined")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Open 3D Viewer") {
                        // TODO: Show 3D boundary editor
                    }
                }
            }
            .navigationTitle("New Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let region = TreatmentRegion(
                            id: UUID(),
                            name: name,
                            type: type,
                            boundaries: boundaries,
                            parameters: .init(
                                density: density,
                                direction: direction,
                                spacing: spacing,
                                maximumDeviation: maxDeviation
                            )
                        )
                        onSave(region)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        !boundaries.isEmpty &&
        boundaries.count >= 3 &&
        density >= 20 && density <= 60 &&
        spacing >= 0.5 && spacing <= 1.5 &&
        maxDeviation >= 0 && maxDeviation <= 30
    }
}
