import Foundation

final class RateLimitManager {
    static let shared = RateLimitManager()
    
    private var attemptCounts: [String: [Date]] = [:]
    private let maxAttempts = 5
    private let timeWindow: TimeInterval = 300 // 5 minutes
    
    private let logger = XcalpLogger.shared
    private let queue = DispatchQueue(label: "com.xcalp.ratelimit")
    
    private init() {}
    
    func checkRateLimit(for identifier: String) -> Bool {
        queue.sync {
            cleanupOldAttempts(for: identifier)
            
            let attempts = attemptCounts[identifier] ?? []
            if attempts.count >= maxAttempts {
                logger.warning("Rate limit exceeded for: \(identifier)")
                return false
            }
            
            attemptCounts[identifier] = (attempts + [Date()])
            return true
        }
    }
    
    func resetAttempts(for identifier: String) {
        queue.sync {
            attemptCounts[identifier] = nil
            logger.info("Rate limit reset for: \(identifier)")
        }
    }
    
    private func cleanupOldAttempts(for identifier: String) {
        let now = Date()
        attemptCounts[identifier] = attemptCounts[identifier]?.filter {
            now.timeIntervalSince($0) < timeWindow
        }
    }
}
