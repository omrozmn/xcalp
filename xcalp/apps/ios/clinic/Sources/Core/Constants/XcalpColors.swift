import SwiftUI

public enum XcalpColors {
    // Primary Brand Colors
    public static let darkNavy = Color(hex: "1E2A4A")    // Technology, premium feel
    public static let lightSilver = Color(hex: "D1D1D1") // Modern, minimal
    
    // Accent & Action Colors
    public static let vibrantBlue = Color(hex: "5A5ECD") // CTA buttons, actions
    public static let softGreen = Color(hex: "53C68C")   // Success messages
    
    // Neutral Colors
    public static let darkGray = Color(hex: "3A3A3A")    // Text and icons
    public static let metallicGray = Color(hex: "848C95") // UI balancing
}

// MARK: - Color Extension for Hex Support
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
            (a, r, g, b) = (255, 0, 0, 0)
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
