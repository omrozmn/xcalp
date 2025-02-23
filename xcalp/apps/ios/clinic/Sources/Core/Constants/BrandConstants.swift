import SwiftUI

public enum XcalpColors {
    public static let primary = Color("Primary", bundle: .module)
    public static let secondary = Color("Secondary", bundle: .module)
    public static let accent = Color("Accent", bundle: .module)
    public static let background = Color("Background", bundle: .module)
    public static let surface = Color("Surface", bundle: .module)
    public static let error = Color("Error", bundle: .module)
    public static let text = Color("Text", bundle: .module)
    public static let textSecondary = Color("TextSecondary", bundle: .module)
}

public enum XcalpTypography {
    public static let largeTitle = Font.largeTitle
    public static let title = Font.title
    public static let title2 = Font.title2
    public static let title3 = Font.title3
    public static let headline = Font.headline
    public static let subheadline = Font.subheadline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let footnote = Font.footnote
    public static let caption = Font.caption
    public static let caption2 = Font.caption2
}

public enum XcalpLayout {
    public static let spacing: CGFloat = 16
    public static let cornerRadius: CGFloat = 12
    public static let buttonHeight: CGFloat = 50
    public static let maxWidth: CGFloat = 414
    public static let minTapTarget: CGFloat = 44
}

public enum XcalpAnimation {
    public static let standard = Animation.easeInOut(duration: 0.3)
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    public static let quick = Animation.easeInOut(duration: 0.15)
}

public enum XcalpHaptics {
    public static let light = UIImpactFeedbackGenerator.FeedbackStyle.light
    public static let medium = UIImpactFeedbackGenerator.FeedbackStyle.medium
    public static let heavy = UIImpactFeedbackGenerator.FeedbackStyle.heavy
}

public enum XcalpPerformance {
    public static let targetFrameRate: Double = 60
    public static let maxMemoryUsageMB: Double = 200
    public static let maxProcessingTimeSeconds: Double = 5
    public static let minDiskSpaceGB: Double = 1
}
