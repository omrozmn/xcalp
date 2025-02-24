import SwiftUI

public struct AppButton: View {
    let title: String
    let action: () -> Void
    let style: Style
    
    public init(
        _ title: String,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(style.backgroundColor)
        .foregroundColor(style.foregroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
    }
    
    public enum Style {
        case primary
        case secondary
        
        var backgroundColor: Color {
            switch self {
            case .primary: return .accentColor
            case .secondary: return .gray.opacity(0.1)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            }
        }
    }
}
