import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private let center = UNUserNotificationCenter.current()
    private let preferences = SecurePreferencesManager.shared
    private let analytics = AnalyticsService.shared
    private let regionManager = RegionalComplianceManager.shared
    
    // Region-specific notification configurations
    private var notificationConfigs: [Region: NotificationConfig] = [
        .unitedStates: .init(
            quietHours: DateInterval(start: 22, end: 8),
            maxDailyNotifications: 5,
            requiresExplicitConsent: true,
            culturalConsiderations: []
        ),
        .europeanUnion: .init(
            quietHours: DateInterval(start: 23, end: 7),
            maxDailyNotifications: 3,
            requiresExplicitConsent: true,
            culturalConsiderations: []
        ),
        .southAsia: .init(
            quietHours: DateInterval(start: 22, end: 6),
            maxDailyNotifications: 4,
            requiresExplicitConsent: true,
            culturalConsiderations: [
                .prayerTimes,
                .religiousHolidays
            ]
        ),
        .mediterranean: .init(
            quietHours: DateInterval(start: 23, end: 7),
            maxDailyNotifications: 4,
            requiresExplicitConsent: true,
            culturalConsiderations: [
                .prayerTimes,
                .religiousHolidays,
                .siesta
            ]
        ),
        .africanDescent: .init(
            quietHours: DateInterval(start: 22, end: 6),
            maxDailyNotifications: 4,
            requiresExplicitConsent: true,
            culturalConsiderations: [
                .religiousHolidays,
                .communityEvents
            ]
        )
    ]
    
    private var notificationCount: [String: Int] = [:]
    private let notificationQueue = DispatchQueue(label: "com.xcalp.clinic.notifications")
    
    private init() {
        setupNotificationHandling()
    }
    
    // MARK: - Public Interface
    
    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        return try await center.requestAuthorization(options: options)
    }
    
    func scheduleNotification(
        _ notification: AppNotification,
        for userId: UUID
    ) async throws {
        let region = regionManager.getCurrentRegion()
        
        // Get user preferences
        guard let preferences: NotificationPreferences = try await preferences.getPreference(.notifications) else {
            throw NotificationError.preferencesNotFound
        }
        
        // Validate against user preferences
        try validateAgainstPreferences(notification, preferences)
        
        // Get regional config
        guard let config = notificationConfigs[region] else {
            throw NotificationError.configurationNotFound(region)
        }
        
        // Check cultural considerations
        try validateCulturalConsiderations(notification, config)
        
        // Check quiet hours
        guard !isInQuietHours(config.quietHours) else {
            throw NotificationError.quietHoursViolation
        }
        
        // Check daily limit
        guard await isDailyLimitAllowed(for: userId, max: config.maxDailyNotifications) else {
            throw NotificationError.dailyLimitExceeded
        }
        
        // Create notification request
        let request = try createNotificationRequest(from: notification, config: config)
        
        // Schedule notification
        try await center.add(request)
        
        // Track notification
        trackNotificationScheduled(notification, region: region)
        
        // Update count
        incrementNotificationCount(for: userId)
    }
    
    func cancelNotification(withId id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationHandling() {
        center.delegate = self
        
        // Reset daily counts at midnight
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.resetDailyCounts()
        }
    }
    
    private func validateAgainstPreferences(
        _ notification: AppNotification,
        _ preferences: NotificationPreferences
    ) throws {
        guard preferences.enabled else {
            throw NotificationError.notificationsDisabled
        }
        
        guard preferences.types.contains(notification.type) else {
            throw NotificationError.notificationTypeDisabled(notification.type)
        }
        
        if let quietHours = preferences.quietHours,
           isInQuietHours(quietHours) {
            throw NotificationError.quietHoursViolation
        }
    }
    
    private func validateCulturalConsiderations(
        _ notification: AppNotification,
        _ config: NotificationConfig
    ) throws {
        for consideration in config.culturalConsiderations {
            switch consideration {
            case .prayerTimes:
                if isPrayerTime() {
                    throw NotificationError.culturalTimingViolation("Prayer time")
                }
            case .religiousHolidays:
                if isReligiousHoliday() {
                    throw NotificationError.culturalTimingViolation("Religious holiday")
                }
            case .siesta:
                if isSiestaTime() {
                    throw NotificationError.culturalTimingViolation("Siesta")
                }
            case .communityEvents:
                if isCommunityEventTime() {
                    throw NotificationError.culturalTimingViolation("Community event")
                }
            }
        }
    }
    
    private func createNotificationRequest(
        from notification: AppNotification,
        config: NotificationConfig
    ) throws -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        
        if let badge = notification.badge {
            content.badge = NSNumber(value: badge)
        }
        
        // Add cultural context if needed
        if let culturalContext = notification.culturalContext {
            content.userInfo["cultural_context"] = culturalContext
        }
        
        let trigger = try createTrigger(for: notification, config: config)
        
        return UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
    }
    
    private func createTrigger(
        for notification: AppNotification,
        config: NotificationConfig
    ) throws -> UNNotificationTrigger {
        switch notification.trigger {
        case .immediate:
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            
        case .scheduled(let date):
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
        case .recurring(let interval):
            return UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: true
            )
        }
    }
    
    private func isDailyLimitAllowed(for userId: UUID, max: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            notificationQueue.async {
                let count = self.notificationCount[userId.uuidString] ?? 0
                continuation.resume(returning: count < max)
            }
        }
    }
    
    private func incrementNotificationCount(for userId: UUID) {
        notificationQueue.async {
            let key = userId.uuidString
            self.notificationCount[key] = (self.notificationCount[key] ?? 0) + 1
        }
    }
    
    private func resetDailyCounts() {
        notificationQueue.async {
            self.notificationCount.removeAll()
        }
    }
    
    private func trackNotificationScheduled(_ notification: AppNotification, region: Region) {
        analytics.trackEvent(
            category: .notifications,
            action: "scheduled",
            label: notification.type.rawValue,
            value: 1,
            metadata: [
                "region": region.rawValue,
                "notification_id": notification.id
            ]
        )
    }
}

// MARK: - Supporting Types

struct NotificationConfig {
    let quietHours: DateInterval
    let maxDailyNotifications: Int
    let requiresExplicitConsent: Bool
    let culturalConsiderations: Set<CulturalConsideration>
}

struct AppNotification {
    let id: String
    let type: NotificationPreferences.NotificationType
    let title: String
    let body: String
    let trigger: NotificationTrigger
    let badge: Int?
    let culturalContext: [String: Any]?
}

enum NotificationTrigger {
    case immediate
    case scheduled(Date)
    case recurring(TimeInterval)
}

enum CulturalConsideration {
    case prayerTimes
    case religiousHolidays
    case siesta
    case communityEvents
}

enum NotificationError: LocalizedError {
    case notificationsDisabled
    case notificationTypeDisabled(NotificationPreferences.NotificationType)
    case preferencesNotFound
    case configurationNotFound(Region)
    case quietHoursViolation
    case dailyLimitExceeded
    case culturalTimingViolation(String)
    
    var errorDescription: String? {
        switch self {
        case .notificationsDisabled:
            return "Notifications are disabled"
        case .notificationTypeDisabled(let type):
            return "Notification type is disabled: \(type)"
        case .preferencesNotFound:
            return "Notification preferences not found"
        case .configurationNotFound(let region):
            return "Notification configuration not found for region: \(region)"
        case .quietHoursViolation:
            return "Cannot send notifications during quiet hours"
        case .dailyLimitExceeded:
            return "Daily notification limit exceeded"
        case .culturalTimingViolation(let reason):
            return "Cultural timing violation: \(reason)"
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification response
        let userInfo = response.notification.request.content.userInfo
        
        analytics.trackEvent(
            category: .notifications,
            action: "interaction",
            label: response.actionIdentifier,
            value: 1,
            metadata: userInfo as? [String: String] ?? [:]
        )
        
        completionHandler()
    }
}

// MARK: - Private Helper Methods

private extension NotificationManager {
    func isInQuietHours(_ interval: DateInterval) -> Bool {
        let now = Date()
        return interval.contains(now)
    }
    
    func isPrayerTime() -> Bool {
        // Implementation would check prayer times
        return false
    }
    
    func isReligiousHoliday() -> Bool {
        // Implementation would check religious holidays
        return false
    }
    
    func isSiestaTime() -> Bool {
        // Implementation would check siesta time
        return false
    }
    
    func isCommunityEventTime() -> Bool {
        // Implementation would check community events
        return false
    }
}