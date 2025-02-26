import Foundation
import CoreData
import os.log

public class ScanningDataStore {
    public static let shared = try! ScanningDataStore()
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningDataStore")
    
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    
    private init() throws {
        let container = NSPersistentContainer(name: "ScanningModel")
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        
        self.persistentContainer = container
        self.backgroundContext = container.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        try configureDatabaseIfNeeded()
    }
    
    // MARK: - Session Management
    
    public func createScanningSession(
        mode: ScanningMode,
        configuration: [String: Any],
        timestamp: Date
    ) async throws -> ScanningSession {
        try await backgroundContext.perform {
            let session = ScanningSession(context: self.backgroundContext)
            session.id = UUID()
            session.mode = mode.rawValue
            session.configuration = configuration as NSDictionary
            session.timestamp = timestamp
            session.status = ScanningSessionStatus.active.rawValue
            
            try self.backgroundContext.save()
            return session
        }
    }
    
    public func updateSessionStatus(
        _ sessionID: UUID,
        status: ScanningSessionStatus
    ) async throws {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<ScanningSession> = ScanningSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
            
            if let session = try fetchRequest.execute().first {
                session.status = status.rawValue
                try self.backgroundContext.save()
            }
        }
    }
    
    // MARK: - Diagnostic Data Storage
    
    public func storeDiagnosticSummary(_ summary: DiagnosticSummary) async throws {
        try await backgroundContext.perform {
            let diagnostic = DiagnosticRecord(context: self.backgroundContext)
            diagnostic.sessionID = summary.sessionID
            diagnostic.timestamp = summary.timestamp
            diagnostic.systemState = try NSKeyedArchiver.archivedData(
                withRootObject: summary.systemState,
                requiringSecureCoding: true
            )
            diagnostic.performanceMetrics = try NSKeyedArchiver.archivedData(
                withRootObject: summary.performance,
                requiringSecureCoding: true
            )
            
            try self.backgroundContext.save()
        }
    }
    
    public func storeQualityIssue(_ issue: QualityIssue) async {
        await backgroundContext.perform {
            let record = QualityIssueRecord(context: self.backgroundContext)
            record.timestamp = issue.timestamp
            record.pointDensity = issue.pointDensity
            record.surfaceCompleteness = issue.surfaceCompleteness
            record.noiseLevel = issue.noiseLevel
            record.featurePreservation = issue.featurePreservation
            
            try? self.backgroundContext.save()
        }
    }
    
    public func storeEnvironmentalIssue(_ issue: EnvironmentalIssue) async {
        await backgroundContext.perform {
            let record = EnvironmentalIssueRecord(context: self.backgroundContext)
            record.type = issue.type.rawValue
            record.timestamp = issue.timestamp
            record.severity = issue.severity.rawValue
            
            try? self.backgroundContext.save()
        }
    }
    
    // MARK: - Data Retrieval
    
    public func getRecentSessions(limit: Int = 10) async throws -> [ScanningSession] {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<ScanningSession> = ScanningSession.fetchRequest()
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \ScanningSession.timestamp, ascending: false)
            ]
            fetchRequest.fetchLimit = limit
            
            return try fetchRequest.execute()
        }
    }
    
    public func getDiagnostics(
        for sessionID: UUID
    ) async throws -> [DiagnosticRecord] {
        try await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<DiagnosticRecord> = DiagnosticRecord.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID as CVarArg)
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \DiagnosticRecord.timestamp, ascending: true)
            ]
            
            return try fetchRequest.execute()
        }
    }
    
    // MARK: - Maintenance
    
    private func configureDatabaseIfNeeded() throws {
        // Check if initial configuration is needed
        let fetchRequest: NSFetchRequest<ScanningSession> = ScanningSession.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        let count = try backgroundContext.count(for: fetchRequest)
        if count == 0 {
            try createInitialConfiguration()
        }
    }
    
    private func createInitialConfiguration() throws {
        // Set up any necessary initial database state
        let defaults = DefaultSettings(context: backgroundContext)
        defaults.lastUpdate = Date()
        defaults.qualityThreshold = 0.85
        defaults.storageLimit = 1000
        
        try backgroundContext.save()
    }
}

// MARK: - Supporting Types

public enum ScanningSessionStatus: String {
    case active
    case completed
    case failed
    case cancelled
}

// MARK: - Core Data Models (these would typically be in the .xcdatamodeld file)
public class ScanningSession: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var mode: String
    @NSManaged public var configuration: NSDictionary
    @NSManaged public var timestamp: Date
    @NSManaged public var status: String
}

public class DiagnosticRecord: NSManagedObject {
    @NSManaged public var sessionID: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var systemState: Data
    @NSManaged public var performanceMetrics: Data
}

public class QualityIssueRecord: NSManagedObject {
    @NSManaged public var timestamp: Date
    @NSManaged public var pointDensity: Float
    @NSManaged public var surfaceCompleteness: Double
    @NSManaged public var noiseLevel: Float
    @NSManaged public var featurePreservation: Float
}

public class EnvironmentalIssueRecord: NSManagedObject {
    @NSManaged public var type: String
    @NSManaged public var timestamp: Date
    @NSManaged public var severity: String
}

public class DefaultSettings: NSManagedObject {
    @NSManaged public var lastUpdate: Date
    @NSManaged public var qualityThreshold: Double
    @NSManaged public var storageLimit: Int32
}