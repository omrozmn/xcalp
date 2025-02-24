import SwiftUI

/// Helper for managing layout direction and dynamic type support
public enum LayoutHelper {
    /// Returns the layout direction for the current locale
    public static var layoutDirection: LayoutDirection {
        Locale.current.languageCode?.matches(pattern: "^(ar|fa|he|ur).*$") == true ? .rightToLeft : .leftToRight
    }
    
    /// Returns true if the current layout direction is right-to-left
    public static var isRTL: Bool {
        layoutDirection == .rightToLeft
    }
    
    /// Scales a given value based on dynamic type size
    /// - Parameter baseSize: The base size to scale
    /// - Returns: The scaled value
    public static func dynamicScale(_ baseSize: CGFloat) -> CGFloat {
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        let scaling = UIFontMetrics.default.scaledValue(for: baseSize)
        return scaling
    }
    
    /// Returns the leading edge padding considering RTL
    public static func leadingPadding(_ value: CGFloat) -> EdgeInsets {
        isRTL ? EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: value) 
              : EdgeInsets(top: 0, leading: value, bottom: 0, trailing: 0)
    }
    
    /// Returns the trailing edge padding considering RTL
    public static func trailingPadding(_ value: CGFloat) -> EdgeInsets {
        isRTL ? EdgeInsets(top: 0, leading: value, bottom: 0, trailing: 0)
              : EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: value)
    }
    
    /// Returns a horizontal offset considering RTL
    public static func horizontalOffset(_ value: CGFloat) -> CGFloat {
        isRTL ? -value : value
    }
}

// MARK: - View Extensions
extension View {
    /// Applies dynamic type scaling to a view's frame
    func dynamicallyScaled(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        self.frame(
            width: width.map { LayoutHelper.dynamicScale($0) },
            height: height.map { LayoutHelper.dynamicScale($0) }
        )
    }
    
    /// Applies RTL-aware horizontal padding
    func rtlPadding(leading: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self.padding(
            .leading, LayoutHelper.isRTL ? trailing : leading
        ).padding(
            .trailing, LayoutHelper.isRTL ? leading : trailing
        )
    }
    
    /// Applies RTL-aware horizontal alignment
    func rtlAlignment(_ alignment: HorizontalAlignment = .leading) -> some View {
        let rtlAlignment: HorizontalAlignment = {
            switch alignment {
            case .leading: return LayoutHelper.isRTL ? .trailing : .leading
            case .trailing: return LayoutHelper.isRTL ? .leading : .trailing
            default: return alignment
            }
        }()
        return self.frame(maxWidth: .infinity, alignment: Alignment(horizontal: rtlAlignment, vertical: .center))
    }
}
