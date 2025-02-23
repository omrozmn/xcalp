import SwiftUI

/// A customizable button component that follows the Xcalp design system
/// 
/// Features:
/// - Multiple styles (primary, secondary, destructive)
/// - Loading state support
/// - Accessibility support
/// - Consistent styling across the app
public struct XcalpButton: View {
    let title: String
    let action: () -> Void
    let style: Style
    let isLoading: Bool
    
    /// Creates a new XcalpButton
    /// - Parameters:
    ///   - title: The button's label text
    ///   - style: The visual style of the button
    ///   - isLoading: Whether to show a loading indicator
    ///   - action: The action to perform when tapped
    public init(
        title: String,
        style: Style = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.textColor))
                        .padding(.trailing, 8)
                        .accessibility(label: Text("Loading"))
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(style.backgroundColor)
            .foregroundColor(style.textColor)
            .cornerRadius(10)
        }
        .disabled(isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoading ? "\(title) loading" : title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to \(title.lowercased())")
    }
    
    /// Defines the visual style of the button
    public enum Style {
        case primary
        case secondary
        case destructive
        
        var backgroundColor: Color {
            switch self {
            case .primary:
                return Color(hex: "5A5ECD") // Vibrant Blue
            case .secondary:
                return Color(hex: "848C95") // Metallic Gray
            case .destructive:
                return Color.red
            }
        }
        
        var textColor: Color {
            switch self {
            case .primary, .secondary, .destructive:
                return .white
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
