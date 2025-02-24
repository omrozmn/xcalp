import SwiftUI

extension LocalizedStringKey {
    // Common
    static let ok = LocalizedStringKey("common.ok")
    static let cancel = LocalizedStringKey("common.cancel")
    static let save = LocalizedStringKey("common.save")
    static let delete = LocalizedStringKey("common.delete")
    static let error = LocalizedStringKey("common.error")
    
    // Auth
    static let loginTitle = LocalizedStringKey("auth.login.title")
    static let loginEmail = LocalizedStringKey("auth.login.email")
    static let loginPassword = LocalizedStringKey("auth.login.password")
    static let loginButton = LocalizedStringKey("auth.login.button")
    static let loginForgot = LocalizedStringKey("auth.login.forgot")
    static let loginBiometric = LocalizedStringKey("auth.login.biometric")
    
    // Scanning
    static let scanTitle = LocalizedStringKey("scan.title")
    static let scanStart = LocalizedStringKey("scan.start")
    static let scanStop = LocalizedStringKey("scan.stop")
    static let scanCapture = LocalizedStringKey("scan.capture")
    
    static func scanQuality(_ quality: ScanningFeature.ScanQuality) -> LocalizedStringKey {
        switch quality {
        case .good:
            return "scan.quality.good"
        case .fair:
            return "scan.quality.fair"
        case .poor:
            return "scan.quality.poor"
        case .unknown:
            return "scan.quality.unknown"
        }
    }
    
    static func scanGuide(_ guide: ScanningFeature.ScanningGuide) -> LocalizedStringKey {
        switch guide {
        case .moveCloser:
            return "scan.guide.move_closer"
        case .moveFarther:
            return "scan.guide.move_farther"
        case .moveSlower:
            return "scan.guide.move_slower"
        case .holdSteady:
            return "scan.guide.hold_steady"
        case .scanComplete:
            return "scan.guide.complete"
        }
    }
    
    // Patient List
    static let patientsTitle = LocalizedStringKey("patients.title")
    static let patientsSearch = LocalizedStringKey("patients.search")
    static let patientsAdd = LocalizedStringKey("patients.add")
    
    static func patientsAge(_ age: Int) -> LocalizedStringKey {
        LocalizedStringKey("patients.age \(age)")
    }
    
    static func patientsLastVisit(_ date: String) -> LocalizedStringKey {
        LocalizedStringKey("patients.last_visit \(date)")
    }
    
    // Settings
    static let settingsTitle = LocalizedStringKey("settings.title")
    static let settingsProfile = LocalizedStringKey("settings.profile")
    static let settingsName = LocalizedStringKey("settings.name")
    static let settingsEmail = LocalizedStringKey("settings.email")
    static let settingsRole = LocalizedStringKey("settings.role")
    static let settingsPreferences = LocalizedStringKey("settings.preferences")
    static let settingsBiometrics = LocalizedStringKey("settings.biometrics")
    static let settingsDarkMode = LocalizedStringKey("settings.dark_mode")
    static let settingsNotifications = LocalizedStringKey("settings.notifications")
}
