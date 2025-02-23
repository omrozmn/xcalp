import SwiftUI

public struct XcalpText: ViewModifier {
    let style: Style
    
    public init(_ style: Style) {
        self.style = style
    }
    
    public func body(content: Content) -> some View {
        content
            .font(style.font)
            .foregroundColor(style.color)
    }
    
    public enum Style {
        case h1
        case h2
        case h3
        case body
        case caption
        
        var font: Font {
            switch self {
            case .h1:
                return .system(.title, design: .rounded).weight(.bold)
            case .h2:
                return .system(.title2, design: .rounded).weight(.semibold)
            case .h3:
                return .system(.title3, design: .rounded).weight(.medium)
            case .body:
                return .system(.body)
            case .caption:
                return .system(.caption)
            }
        }
        
        var color: Color {
            switch self {
            case .h1, .h2, .h3:
                return Color(hex: "1E2A4A") // Dark Navy
            case .body:
                return Color(hex: "3A3A3A") // Dark Gray
            case .caption:
                return Color(hex: "848C95") // Metallic Gray
            }
        }
    }
}

extension View {
    func xcalpText(_ style: XcalpText.Style) -> some View {
        modifier(XcalpText(style))
    }
}
