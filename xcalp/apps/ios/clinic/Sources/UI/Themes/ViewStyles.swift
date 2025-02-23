import SwiftUI

// MARK: - Text Styles
struct XcalpText: ViewModifier {
    enum Style {
        case h1, h2, h3, body, caption, small
    }
    
    let style: Style
    
    func body(content: Content) -> some View {
        switch style {
        case .h1:
            content
                .font(.custom(BrandConstants.Typography.headerFontName, size: BrandConstants.Typography.Size.h1))
                .foregroundColor(BrandConstants.Colors.darkGray)
        case .h2:
            content
                .font(.custom(BrandConstants.Typography.headerFontName, size: BrandConstants.Typography.Size.h2))
                .foregroundColor(BrandConstants.Colors.darkGray)
        case .h3:
            content
                .font(.custom(BrandConstants.Typography.headerFontName, size: BrandConstants.Typography.Size.h3))
                .foregroundColor(BrandConstants.Colors.darkGray)
        case .body:
            content
                .font(.custom(BrandConstants.Typography.bodyFontName, size: BrandConstants.Typography.Size.body))
                .foregroundColor(BrandConstants.Colors.darkGray)
        case .caption:
            content
                .font(.custom(BrandConstants.Typography.bodyFontName, size: BrandConstants.Typography.Size.caption))
                .foregroundColor(BrandConstants.Colors.metallicGray)
        case .small:
            content
                .font(.custom(BrandConstants.Typography.bodyFontName, size: BrandConstants.Typography.Size.small))
                .foregroundColor(BrandConstants.Colors.metallicGray)
        }
    }
}

// MARK: - Button Styles
struct XcalpButton: ButtonStyle {
    enum Style {
        case primary, secondary, tertiary
    }
    
    let style: Style
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        switch style {
        case .primary:
            configuration.label
                .frame(maxWidth: .infinity)
                .frame(height: BrandConstants.Layout.buttonHeight)
                .background(isEnabled ? BrandConstants.Colors.vibrantBlue : BrandConstants.Colors.metallicGray)
                .foregroundColor(.white)
                .cornerRadius(BrandConstants.Layout.cornerRadius)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        case .secondary:
            configuration.label
                .frame(maxWidth: .infinity)
                .frame(height: BrandConstants.Layout.buttonHeight)
                .background(BrandConstants.Colors.lightSilver)
                .foregroundColor(BrandConstants.Colors.darkNavy)
                .cornerRadius(BrandConstants.Layout.cornerRadius)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        case .tertiary:
            configuration.label
                .frame(maxWidth: .infinity)
                .frame(height: BrandConstants.Layout.buttonHeight)
                .foregroundColor(BrandConstants.Colors.vibrantBlue)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }
}

// MARK: - Input Field Styles
struct XcalpTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.white)
            .cornerRadius(BrandConstants.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: BrandConstants.Layout.cornerRadius)
                    .stroke(BrandConstants.Colors.lightSilver, lineWidth: 1)
            )
    }
}

// MARK: - Card Styles
struct XcalpCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.white)
            .cornerRadius(BrandConstants.Layout.cornerRadius)
            .shadow(
                color: BrandConstants.Colors.darkGray.opacity(0.1),
                radius: 10,
                x: 0,
                y: 2
            )
    }
}

// MARK: - View Extensions
extension View {
    func xcalpText(_ style: XcalpText.Style) -> some View {
        modifier(XcalpText(style: style))
    }
    
    func xcalpTextField() -> some View {
        modifier(XcalpTextField())
    }
    
    func xcalpCard() -> some View {
        modifier(XcalpCard())
    }
}

// MARK: - Navigation Bar Style
struct XcalpNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(BrandConstants.Colors.darkNavy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func xcalpNavigationBar() -> some View {
        modifier(XcalpNavigationBar())
    }
}
