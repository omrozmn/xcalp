import SwiftUI

public struct SessionManagementView: View {
    @ObservedObject var viewModel: ScanningFeature
    @Environment(\.presentationMode) var presentationMode
    @State private var showingDeleteConfirmation = false
    @State private var sessionToDelete: ScanSession?
    
    public var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.availableSessions, id: \.id) { session in
                    SessionRow(
                        session: session,
                        onResume: {
                            Task {
                                await viewModel.resumeSession(session)
                                presentationMode.wrappedValue.dismiss()
                            }
                        },
                        onDelete: {
                            sessionToDelete = session
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .navigationTitle("Saved Scans")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Delete Scan"),
                    message: Text("Are you sure you want to delete this scan? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let session = sessionToDelete {
                            viewModel.deleteSession(session)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

private struct SessionRow: View {
    let session: ScanSession
    let onResume: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.headline)
                
                Text("Quality: \(Int(session.quality * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if session.isRecent {
                    Text("Recent")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onResume) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.timestamp)
    }
}