import SwiftUI

public enum XcalpTypography {
    // MARK: - Font Families
    public static let primaryFont = "Montserrat"
    public static let bodyFont = "Inter"
    
    // MARK: - Font Sizes
    public enum Size {
        public static let h1: CGFloat = 32
        public static let h2: CGFloat = 24
        public static let h3: CGFloat = 20
        public static let body: CGFloat = 16
        public static let caption: CGFloat = 14
        public static let small: CGFloat = 12
    }
    
    // MARK: - Font Styles
    public static func heading1() -> Font {
        .custom(primaryFont, size: Size.h1, relativeTo: .title)
    }
    
    public static func heading2() -> Font {
        .custom(primaryFont, size: Size.h2, relativeTo: .title2)
    }
    
    public static func heading3() -> Font {
        .custom(primaryFont, size: Size.h3, relativeTo: .title3)
    }
    
    public static func bodyRegular() -> Font {
        .custom(bodyFont, size: Size.body, relativeTo: .body)
    }
    
    public static func bodyBold() -> Font {
        .custom(bodyFont, size: Size.body, relativeTo: .body).bold()
    }
    
    public static func caption() -> Font {
        .custom(bodyFont, size: Size.caption, relativeTo: .caption)
    }
    
    public static func small() -> Font {
        .custom(bodyFont, size: Size.small, relativeTo: .caption2)
    }
}

// MARK: - Text Style Extension
extension Text {
    func xcalpStyle(_ style: XcalpTypography.Type = XcalpTypography.self) -> Text {
        self.font(style.bodyRegular())
            .foregroundColor(XcalpColors.darkGray)
    }
    
    func xcalpHeading1() -> Text {
        self.font(XcalpTypography.heading1())
            .foregroundColor(XcalpColors.darkNavy)
    }
    
    func xcalpHeading2() -> Text {
        self.font(XcalpTypography.heading2())
            .foregroundColor(XcalpColors.darkNavy)
    }
    
    func xcalpHeading3() -> Text {
        self.font(XcalpTypography.heading3())
            .foregroundColor(XcalpColors.darkNavy)
    }
    
    func xcalpCaption() -> Text {
        self.font(XcalpTypography.caption())
            .foregroundColor(XcalpColors.metallicGray)
    }
}
