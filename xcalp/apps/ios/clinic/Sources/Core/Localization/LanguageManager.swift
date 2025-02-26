import Foundation

class LanguageManager {
    static let shared = LanguageManager()
    
    // Supported languages with their locales and native names
    private let supportedLanguages: [Language] = [
        Language(code: "en", locale: "en_US", nativeName: "English", direction: .leftToRight),
        Language(code: "tr", locale: "tr_TR", nativeName: "Türkçe", direction: .leftToRight),
        Language(code: "ar", locale: "ar_SA", nativeName: "العربية", direction: .rightToLeft),
        Language(code: "es", locale: "es_ES", nativeName: "Español", direction: .leftToRight),
        Language(code: "fr", locale: "fr_FR", nativeName: "Français", direction: .leftToRight),
        Language(code: "de", locale: "de_DE", nativeName: "Deutsch", direction: .leftToRight),
        Language(code: "zh", locale: "zh_CN", nativeName: "中文", direction: .leftToRight),
        Language(code: "ja", locale: "ja_JP", nativeName: "日本語", direction: .leftToRight),
        Language(code: "ko", locale: "ko_KR", nativeName: "한국어", direction: .leftToRight),
        Language(code: "hi", locale: "hi_IN", nativeName: "हिन्दी", direction: .leftToRight)
    ]
    
    private var currentLanguage: Language
    private var fallbackLanguage: Language
    
    private init() {
        // Initialize with system language or fallback to English
        let systemLanguage = Locale.current.languageCode ?? "en"
        self.currentLanguage = supportedLanguages.first { $0.code == systemLanguage } ?? Language(code: "en", locale: "en_US", nativeName: "English", direction: .leftToRight)
        self.fallbackLanguage = Language(code: "en", locale: "en_US", nativeName: "English", direction: .leftToRight)
    }
    
    func availableLanguages() -> [Language] {
        return supportedLanguages
    }
    
    func setLanguage(_ code: String) throws {
        guard let language = supportedLanguages.first(where: { $0.code == code }) else {
            throw LocalizationError.unsupportedLanguage(code)
        }
        
        currentLanguage = language
        
        // Update system configurations
        UserDefaults.standard.set([language.code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Update bundle
        Bundle.setLanguage(language.code)
        
        // Notify system of language change
        NotificationCenter.default.post(
            name: .languageDidChange,
            object: nil,
            userInfo: ["language": language]
        )
    }
    
    func getCurrentLanguage() -> Language {
        return currentLanguage
    }
    
    func getTextDirection() -> TextDirection {
        return currentLanguage.direction
    }
    
    // Number formatting based on locale
    func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: currentLanguage.locale)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    // Date formatting based on locale
    func formatDate(_ date: Date, style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: currentLanguage.locale)
        formatter.dateStyle = style
        return formatter.string(from: date)
    }
    
    // Currency formatting based on locale
    func formatCurrency(_ amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: currentLanguage.locale)
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

struct Language: Codable, Equatable {
    let code: String
    let locale: String
    let nativeName: String
    let direction: TextDirection
}

enum TextDirection: String, Codable {
    case leftToRight = "ltr"
    case rightToLeft = "rtl"
}

enum LocalizationError: Error {
    case unsupportedLanguage(String)
    case invalidLocaleIdentifier
    case resourceNotFound
}

// Bundle extension for language support
extension Bundle {
    private static var _bundle: Bundle?
    
    static func setLanguage(_ languageCode: String) {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            _bundle = Bundle.main
            return
        }
        _bundle = bundle
    }
    
    static func localizedBundle() -> Bundle {
        return _bundle ?? Bundle.main
    }
}