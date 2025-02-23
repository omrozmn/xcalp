import SwiftUI

public enum AppTheme {
    public enum Colors {
        public static let primary = Color.accentColor
        public static let secondary = Color(uiColor: .systemGray5)
        public static let background = Color(uiColor: .systemBackground)
        public static let error = Color.red
        public static let success = Color.green
        
        public enum Text {
            public static let primary = Color.primary
            public static let secondary = Color.secondary
            public static let accent = Color.accentColor
        }
    }
    
    public enum Layout {
        public static let screenPadding: CGFloat = 16
        public static let itemSpacing: CGFloat = 12
        public static let cornerRadius: CGFloat = 12
        public static let buttonHeight: CGFloat = 50
    }
    
    public enum Typography {
        public static let titleLarge = Font.largeTitle.weight(.bold)
        public static let title = Font.title.weight(.semibold)
        public static let headline = Font.headline
        public static let body = Font.body
        public static let caption = Font.caption
    }
}

// MARK: - View Extensions
public extension View {
    func screenPadding() -> some View {
        padding(EdgeInsets(
            top: AppTheme.Layout.screenPadding,
            leading: AppTheme.Layout.screenPadding,
            bottom: AppTheme.Layout.screenPadding,
            trailing: AppTheme.Layout.screenPadding
        ))
    }
}