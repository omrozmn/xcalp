import Foundation
import CoreLocation

class LocalizationManager {
    static let shared = LocalizationManager()
    private let regionManager = RegionalComplianceManager.shared
    private let locationManager = LocationManager.shared
    private let userDefaults = UserDefaults.standard
    private let storageManager = SecureStorage.shared
    
    // Default localization settings per region
    private var defaultSettings: [String: CulturalSettings] = [
        "US": .init(
            measurementSystem: .imperial,
            dateFormat: "MM/dd/yyyy",
            timeFormat: "h:mm a",
            currencyCode: "USD",
            textDirection: .leftToRight,
            numberFormat: .init(
                decimalSeparator: ".",
                groupingSeparator: ","
            )
        ),
        "GB": .init(
            measurementSystem: .imperial,
            dateFormat: "dd/MM/yyyy",
            timeFormat: "HH:mm",
            currencyCode: "GBP",
            textDirection: .leftToRight,
            numberFormat: .init(
                decimalSeparator: ".",
                groupingSeparator: ","
            )
        ),
        "TR": .init(
            measurementSystem: .metric,
            dateFormat: "dd.MM.yyyy",
            timeFormat: "HH:mm",
            currencyCode: "TRY",
            textDirection: .leftToRight,
            numberFormat: .init(
                decimalSeparator: ",",
                groupingSeparator: "."
            )
        ),
        "SA": .init(
            measurementSystem: .metric,
            dateFormat: "dd/MM/yyyy",
            timeFormat: "HH:mm",
            currencyCode: "SAR",
            textDirection: .rightToLeft,
            numberFormat: .init(
                decimalSeparator: "٫",
                groupingSeparator: "٬"
            )
        )
    ]
    
    private var currentLocale: Locale
    private var observers: [LocalizationObserver] = []
    
    private init() {
        self.currentLocale = Locale.current
        setupObservers()
        loadStoredSettings()
    }
    
    // MARK: - Public Interface
    
    func setLocale(_ identifier: String) {
        guard let locale = Locale(identifier: identifier) else { return }
        currentLocale = locale
        
        // Update region if needed
        if let regionCode = locale.regionCode,
           regionCode != regionManager.getCurrentRegion().rawValue {
            try? regionManager.setRegion(Region(rawValue: regionCode) ?? .unitedStates)
        }
        
        // Notify observers
        notifyObservers()
        
        // Persist settings
        saveSettings()
    }
    
    func getCurrentSettings() -> CulturalSettings {
        let regionCode = currentLocale.regionCode ?? "US"
        return defaultSettings[regionCode] ?? .default
    }
    
    func addObserver(_ observer: LocalizationObserver) {
        observers.append(observer)
    }
    
    func removeObserver(_ observer: LocalizationObserver) {
        observers.removeAll { $0 === observer }
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRegionChange),
            name: .regionDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSignificantLocationChange),
            name: NSNotification.Name("significantLocationChange"),
            object: nil
        )
    }
    
    @objc private func handleRegionChange(_ notification: Notification) {
        guard let region = notification.userInfo?["region"] as? Region else { return }
        updateLocaleForRegion(region)
    }
    
    @objc private func handleSignificantLocationChange(_ notification: Notification) {
        guard let countryCode = notification.userInfo?["countryCode"] as? String,
              let region = Region(rawValue: countryCode) else { return }
        updateLocaleForRegion(region)
    }
    
    private func updateLocaleForRegion(_ region: Region) {
        let languageCode = currentLocale.languageCode ?? "en"
        let identifier = "\(languageCode)_\(region.rawValue)"
        setLocale(identifier)
    }
    
    private func notifyObservers() {
        observers.forEach { observer in
            observer.localizationDidChange(to: currentLocale)
        }
    }
    
    private func loadStoredSettings() {
        Task {
            if let storedSettings = try? await storageManager.retrieve(
                [String: CulturalSettings].self,
                forKey: "localization_settings"
            ) {
                defaultSettings = storedSettings
            }
        }
    }
    
    private func saveSettings() {
        Task {
            try? await storageManager.store(
                defaultSettings,
                forKey: "localization_settings",
                expires: .never
            )
        }
    }
}

// MARK: - Supporting Types

protocol LocalizationObserver: AnyObject {
    func localizationDidChange(to locale: Locale)
}

struct CulturalSettings {
    let measurementSystem: MeasurementSystem
    let dateFormat: String
    let timeFormat: String
    let currencyCode: String
    let textDirection: TextDirection
    let numberFormat: NumberFormat
    
    static let `default` = CulturalSettings(
        measurementSystem: .metric,
        dateFormat: "yyyy-MM-dd",
        timeFormat: "HH:mm",
        currencyCode: "USD",
        textDirection: .leftToRight,
        numberFormat: NumberFormat(
            decimalSeparator: ".",
            groupingSeparator: ","
        )
    )
}

enum MeasurementSystem {
    case metric
    case imperial
}

enum TextDirection {
    case leftToRight
    case rightToLeft
}

struct NumberFormat {
    let decimalSeparator: String
    let groupingSeparator: String
}