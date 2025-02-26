import Foundation
import CoreData
import Combine
import os.log

final class ScanningDataStore {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningDataStore")
    private let persistentContainer: NSPersistentContainer
    private var cancellables = Set<AnyCancellable>()
    
    static let shared = try! ScanningDataStore()
    
    private init() throws {
        persistentContainer = NSPersistentContainer(name: "ScanningData")
        
        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = NSSQLiteStoreType
        
        // Enable data protection
        storeDescription.setOption(FileProtectionType.complete as NSObject,
                                 forKey: NSPersistentStoreFileProtectionKey)
        
        persistentContainer.persistentStoreDescriptor = storeDescription
        
        var initError: Error?
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                initError = error
            }
        }
        
        if let error = initError {
            throw error
        }
        
        // Setup automatic saving
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                try? self?.saveContext()
            }
            .store(in: &cancellables)
    }
    
    func saveContext() throws {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            try context.save()
        }
    }
    
    // MARK: - Scanning Session Management
    
    func createScanningSession(
        mode: ScanningMode,
        configuration: [String: Any],
        timestamp: Date = Date()
    ) throws -> ScanningSession {
        let context = persistentContainer.viewContext
        let session = ScanningSession(context: context)
        
        session.id = UUID()
        session.mode = mode.rawValue
        session.timestamp = timestamp
        session.configuration = try JSONSerialization.data(withJSONObject: configuration)
        
        try context.save()
        return session
    }
    
    func updateSession(
        _ session: ScanningSession,
        withQualityReport report: MeshQualityAnalyzer.QualityReport
    ) throws {
        let context = persistentContainer.viewContext
        
        let qualityRecord = QualityRecord(context: context)
        qualityRecord.timestamp = Date()
        qualityRecord.pointDensity = report.pointDensity
        qualityRecord.surfaceCompleteness = report.surfaceCompleteness
        qualityRecord.noiseLevel = report.noiseLevel
        qualityRecord.featurePreservation = report.featurePreservation
        qualityRecord.session = session
        
        try context.save()
    }
    
    func fetchRecentSessions(limit: Int = 10) throws -> [ScanningSession] {
        let context = persistentContainer.viewContext
        let request = ScanningSession.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        return try context.fetch(request)
    }
    
    // MARK: - Optimization History
    
    func recordOptimizationDecision(
        fromMode: ScanningMode,
        toMode: ScanningMode,
        conditions: ScanningConditions,
        result: OptimizationResult
    ) throws {
        let context = persistentContainer.viewContext
        let record = OptimizationRecord(context: context)
        
        record.id = UUID()
        record.timestamp = Date()
        record.fromMode = fromMode.rawValue
        record.toMode = toMode.rawValue
        record.lightingLevel = conditions.lightingLevel
        record.motionStability = conditions.motionStability
        record.surfaceComplexity = conditions.surfaceComplexity
        record.devicePerformance = conditions.devicePerformance
        record.success = result.success
        record.reason = result.reason
        
        try context.save()
    }
    
    func fetchOptimizationHistory(
        forMode mode: ScanningMode,
        limit: Int = 50
    ) throws -> [OptimizationRecord] {
        let context = persistentContainer.viewContext
        let request = OptimizationRecord.fetchRequest()
        
        request.predicate = NSPredicate(
            format: "fromMode = %@ OR toMode = %@",
            mode.rawValue, mode.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        return try context.fetch(request)
    }
    
    // MARK: - Quality Metrics
    
    func fetchQualityHistory(
        forSession session: ScanningSession
    ) throws -> [QualityRecord] {
        let context = persistentContainer.viewContext
        let request = QualityRecord.fetchRequest()
        
        request.predicate = NSPredicate(format: "session = %@", session)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        return try context.fetch(request)
    }
    
    func calculateAverageQualityMetrics(
        forMode mode: ScanningMode,
        timeRange: TimeInterval = 86400 // 24 hours
    ) throws -> QualityMetrics {
        let context = persistentContainer.viewContext
        let request = QualityRecord.fetchRequest()
        
        let cutoffDate = Date().addingTimeInterval(-timeRange)
        request.predicate = NSPredicate(
            format: "session.mode = %@ AND timestamp > %@",
            mode.rawValue, cutoffDate as NSDate
        )
        
        let records = try context.fetch(request)
        
        // Calculate averages
        let averages = records.reduce(into: QualityMetrics()) { metrics, record in
            metrics.pointDensity += record.pointDensity
            metrics.surfaceCompleteness += record.surfaceCompleteness
            metrics.noiseLevel += record.noiseLevel
            metrics.featurePreservation += record.featurePreservation
        }
        
        let count = Float(records.count)
        if count > 0 {
            averages.pointDensity /= count
            averages.surfaceCompleteness /= count
            averages.noiseLevel /= count
            averages.featurePreservation /= count
        }
        
        return averages
    }
    
    // MARK: - Configuration Management
    
    func saveOptimalConfiguration(
        forMode mode: ScanningMode,
        configuration: [String: Any],
        conditions: ScanningConditions
    ) throws {
        let context = persistentContainer.viewContext
        let config = OptimalConfiguration(context: context)
        
        config.id = UUID()
        config.mode = mode.rawValue
        config.timestamp = Date()
        config.configuration = try JSONSerialization.data(withJSONObject: configuration)
        config.lightingLevel = conditions.lightingLevel
        config.motionStability = conditions.motionStability
        config.surfaceComplexity = conditions.surfaceComplexity
        
        try context.save()
    }
    
    func fetchOptimalConfiguration(
        forMode mode: ScanningMode,
        conditions: ScanningConditions
    ) throws -> [String: Any]? {
        let context = persistentContainer.viewContext
        let request = OptimalConfiguration.fetchRequest()
        
        // Find configurations for similar conditions
        request.predicate = NSPredicate(
            format: """
                mode = %@ AND
                ABS(lightingLevel - %f) < 0.2 AND
                ABS(motionStability - %f) < 0.2 AND
                ABS(surfaceComplexity - %f) < 0.2
            """,
            mode.rawValue,
            conditions.lightingLevel,
            conditions.motionStability,
            conditions.surfaceComplexity
        )
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1
        
        guard let config = try context.fetch(request).first,
              let data = config.configuration else {
            return nil
        }
        
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Supporting Types

struct QualityMetrics {
    var pointDensity: Float = 0
    var surfaceCompleteness: Float = 0
    var noiseLevel: Float = 0
    var featurePreservation: Float = 0
}

struct OptimizationResult {
    let success: Bool
    let reason: String
    let metrics: QualityMetrics?
}

// MARK: - Core Data Model Extensions

extension ScanningSession {
    var qualityRecords: [QualityRecord] {
        (records?.allObjects as? [QualityRecord]) ?? []
    }
    
    var averageQuality: QualityMetrics {
        let records = qualityRecords
        guard !records.isEmpty else { return QualityMetrics() }
        
        return records.reduce(into: QualityMetrics()) { metrics, record in
            metrics.pointDensity += record.pointDensity
            metrics.surfaceCompleteness += record.surfaceCompleteness
            metrics.noiseLevel += record.noiseLevel
            metrics.featurePreservation += record.featurePreservation
        }.normalized(by: Float(records.count))
    }
}

private extension QualityMetrics {
    func normalized(by factor: Float) -> QualityMetrics {
        var metrics = self
        metrics.pointDensity /= factor
        metrics.surfaceCompleteness /= factor
        metrics.noiseLevel /= factor
        metrics.featurePreservation /= factor
        return metrics
    }
}