import Foundation

enum AppConfig {
    // Quality Thresholds
    static let minimumPhotoQuality: Float = 0.85
    static let minimumLightingScore: Float = 800.0  // Lux
    static let minimumScanQuality: Float = 0.95
    static let minimumInstructionsVersion: Int = 2
    
    // Performance Thresholds
    static let maxProcessingTime: TimeInterval = 5.0
    static let maxMemoryUsage: Int64 = 750 * 1024 * 1024  // 750MB
    static let maxDiskUsage: Int64 = 100 * 1024 * 1024    // 100MB
    static let maxNetworkLatency: TimeInterval = 0.5       // 500ms
    
    // Cache Configuration
    static let maxCacheSize: Int64 = 500 * 1024 * 1024    // 500MB
    static let cacheExpirationDays: Int = 30
    static let maxCachedItems: Int = 1000
    
    // Security Settings
    static let keyLength: Int = 256                        // bits
    static let saltLength: Int = 32                        // bytes
    static let pbkdfRounds: Int = 10000
    static let sessionTimeout: TimeInterval = 1800         // 30 minutes
    
    // Cultural Settings
    enum CulturalDefaults {
        static let measurementSystems: [Region: MeasurementSystem] = [
            .unitedStates: .imperial,
            .europeanUnion: .metric,
            .turkey: .metric,
            .japanKorea: .metric,
            .middleEast: .metric,
            .australia: .metric,
            .southAsia: .metric,
            .mediterranean: .metric,
            .africanDescent: .metric
        ]
        
        static let languagesByRegion: [Region: [String]] = [
            .unitedStates: ["en"],
            .europeanUnion: ["en", "de", "fr", "es", "it"],
            .turkey: ["tr", "en"],
            .japanKorea: ["ja", "ko", "en"],
            .middleEast: ["ar", "en"],
            .australia: ["en"],
            .southAsia: ["hi", "en", "bn"],
            .mediterranean: ["el", "tr", "ar", "en"],
            .africanDescent: ["en", "fr", "ar", "sw"]
        ]
        
        static let textDirections: [Region: TextDirection] = [
            .unitedStates: .leftToRight,
            .europeanUnion: .leftToRight,
            .turkey: .leftToRight,
            .japanKorea: .leftToRight,
            .middleEast: .rightToLeft,
            .australia: .leftToRight,
            .southAsia: .leftToRight,
            .mediterranean: .leftToRight,
            .africanDescent: .leftToRight
        ]
        
        static let dateFormats: [Region: String] = [
            .unitedStates: "MM/dd/yyyy",
            .europeanUnion: "dd.MM.yyyy",
            .turkey: "dd.MM.yyyy",
            .japanKorea: "yyyy-MM-dd",
            .middleEast: "dd/MM/yyyy",
            .australia: "dd/MM/yyyy",
            .southAsia: "dd/MM/yyyy",
            .mediterranean: "dd/MM/yyyy",
            .africanDescent: "dd/MM/yyyy"
        ]
    }
    
    // Workflow Settings
    enum WorkflowDefaults {
        static let consentValidityDays: [Region: Int] = [
            .unitedStates: 365,     // 1 year
            .europeanUnion: 365,    // 1 year
            .turkey: 365,           // 1 year
            .japanKorea: 180,       // 6 months
            .middleEast: 365,       // 1 year
            .australia: 365,        // 1 year
            .southAsia: 180,        // 6 months
            .mediterranean: 365,     // 1 year
            .africanDescent: 180    // 6 months
        ]
        
        static let requiredPhotoAngles: [Region: [Int]] = [
            .unitedStates: [0, 45, 90, 180, 270, 315],
            .europeanUnion: [0, 45, 90, 135, 180, 225, 270, 315],
            .turkey: [0, 45, 90, 180, 270, 315],
            .japanKorea: [0, 45, 90, 135, 180, 225, 270, 315],
            .middleEast: [0, 45, 90, 135, 180, 225, 270, 315],
            .australia: [0, 45, 90, 180, 270, 315],
            .southAsia: [0, 45, 90, 135, 180, 225, 270, 315],
            .mediterranean: [0, 45, 90, 135, 180, 225, 270, 315],
            .africanDescent: [0, 45, 90, 135, 180, 225, 270, 315]
        ]
        
        static let culturalAssessmentFields: [Region: Set<String>] = [
            .southAsia: ["religious_requirements", "traditional_styles", "family_patterns"],
            .mediterranean: ["traditional_styles", "family_patterns", "cultural_preferences"],
            .africanDescent: ["hair_texture", "traditional_styles", "cultural_heritage"]
        ]
    }
    
    // Analytics Settings
    enum AnalyticsConfig {
        static let bufferSize: Int = 100
        static let flushInterval: TimeInterval = 300  // 5 minutes
        static let retentionDays: Int = 30
        static let samplingRate: Double = 1.0         // 100%
        
        static let criticalMetrics: Set<String> = [
            "scan_quality",
            "compliance_validation",
            "cultural_analysis",
            "workflow_completion"
        ]
        
        static let performanceMetrics: Set<String> = [
            "processing_time",
            "memory_usage",
            "scan_duration",
            "analysis_latency"
        ]
    }
    
    // Notification Settings
    enum NotificationConfig {
        static let defaultQuietHours: [Region: DateInterval] = [
            .unitedStates: DateInterval(start: 22, end: 8),
            .europeanUnion: DateInterval(start: 23, end: 7),
            .turkey: DateInterval(start: 22, end: 6),
            .japanKorea: DateInterval(start: 23, end: 7),
            .middleEast: DateInterval(start: 22, end: 5),
            .australia: DateInterval(start: 22, end: 7),
            .southAsia: DateInterval(start: 22, end: 6),
            .mediterranean: DateInterval(start: 23, end: 7),
            .africanDescent: DateInterval(start: 22, end: 6)
        ]
        
        static let maxDailyNotifications: [Region: Int] = [
            .unitedStates: 5,
            .europeanUnion: 3,
            .turkey: 4,
            .japanKorea: 3,
            .middleEast: 4,
            .australia: 5,
            .southAsia: 4,
            .mediterranean: 4,
            .africanDescent: 4
        ]
        
        static let culturalConsiderations: [Region: Set<CulturalConsideration>] = [
            .middleEast: [.prayerTimes, .religiousHolidays],
            .southAsia: [.prayerTimes, .religiousHolidays],
            .mediterranean: [.prayerTimes, .religiousHolidays, .siesta],
            .africanDescent: [.religiousHolidays, .communityEvents]
        ]
    }
}

// MARK: - Supporting Extensions

extension DateInterval {
    init(start startHour: Int, end endHour: Int) {
        let calendar = Calendar.current
        let now = Date()
        
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = startHour
        startComponents.minute = 0
        startComponents.second = 0
        
        var endComponents = calendar.dateComponents([.year, .month, .day], from: now)
        endComponents.hour = endHour
        endComponents.minute = 0
        endComponents.second = 0
        
        // If end hour is less than start hour, it means the interval crosses midnight
        if endHour < startHour {
            endComponents = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: 1, to: now)!)
            endComponents.hour = endHour
        }
        
        self.init(
            start: calendar.date(from: startComponents)!,
            end: calendar.date(from: endComponents)!
        )
    }
}