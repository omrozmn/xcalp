import SwiftUI

struct OptimizationHintsView: View {
    let hints: [OptimizationHint]
    @State private var showingFullGuide = false
    
    var body: some View {
        VStack(spacing: 12) {
            if let highPriorityHint = hints.first(where: { $0.priority >= 4 }) {
                // Primary hint card
                HintCard(hint: highPriorityHint, isExpanded: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if hints.count > 1 {
                Button(action: { showingFullGuide.toggle() }) {
                    HStack {
                        Text("\(hints.count - 1) more suggestions")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showingFullGuide ? 90 : 0))
                            .animation(.spring(), value: showingFullGuide)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                }
                
                if showingFullGuide {
                    // Secondary hints
                    ForEach(hints.filter { $0.priority < 4 }, id: \.title) { hint in
                        HintCard(hint: hint, isExpanded: false)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .animation(.spring(), value: showingFullGuide)
    }
}

private struct HintCard: View {
    let hint: OptimizationHint
    let isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(priorityColor)
                
                Text(hint.title)
                    .font(.headline)
                    .foregroundColor(priorityColor)
                
                Spacer()
                
                if hint.actionRequired {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                }
            }
            
            if isExpanded {
                Text(hint.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding()
        .background(Color(white: 0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(priorityColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch hint.priority {
        case 5:
            return "exclamationmark.triangle.fill"
        case 4:
            return "exclamationmark.circle.fill"
        case 3:
            return "info.circle.fill"
        default:
            return "lightbulb.fill"
        }
    }
    
    private var priorityColor: Color {
        switch hint.priority {
        case 5:
            return .red
        case 4:
            return .orange
        case 3:
            return .yellow
        default:
            return .blue
        }
    }
}

#if DEBUG
struct OptimizationHintsView_Previews: PreviewProvider {
    static var previews: some View {
        OptimizationHintsView(hints: [
            OptimizationHint(
                title: "Improve Scanning Pattern",
                description: "Use systematic side-to-side or top-to-bottom scanning motion",
                priority: 5,
                actionRequired: true
            ),
            OptimizationHint(
                title: "Lighting Suggestion",
                description: "Move to an area with better lighting",
                priority: 3,
                actionRequired: false
            ),
            OptimizationHint(
                title: "Coverage Tip",
                description: "Remember to scan edges and corners",
                priority: 2,
                actionRequired: false
            )
        ])
        .preferredColorScheme(.dark)
        .padding()
    }
}