import Foundation
import RealityKit

public struct ScanSession: Codable {
    let id: UUID
    let timestamp: Date
    let points: [Point3D]
    let quality: Float
    let metadata: [String: String]
    
    var isRecent: Bool {
        // Consider sessions from last 24 hours as recent
        return Date().timeIntervalSince(timestamp) < 86400
    }
}

public class ScanningSessionStorage {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var sessionsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("ScanSessions")
    }
    
    public init() {
        createSessionsDirectoryIfNeeded()
    }
    
    private func createSessionsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: sessionsDirectory.path) {
            try? fileManager.createDirectory(
                at: sessionsDirectory,
                withIntermediateDirectories: true
            )
        }
    }
    
    public func saveSession(_ session: ScanSession) throws {
        let sessionURL = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).scan")
        let data = try encoder.encode(session)
        try data.write(to: sessionURL)
    }
    
    public func loadSession(id: UUID) throws -> ScanSession {
        let sessionURL = sessionsDirectory.appendingPathComponent("\(id.uuidString).scan")
        let data = try Data(contentsOf: sessionURL)
        return try decoder.decode(ScanSession.self, from: data)
    }
    
    public func listSessions() throws -> [ScanSession] {
        let sessionFiles = try fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        return try sessionFiles.compactMap { url in
            guard url.pathExtension == "scan" else { return nil }
            let data = try Data(contentsOf: url)
            return try? decoder.decode(ScanSession.self, from: data)
        }
        .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func deleteSession(id: UUID) throws {
        let sessionURL = sessionsDirectory.appendingPathComponent("\(id.uuidString).scan")
        try fileManager.removeItem(at: sessionURL)
    }
    
    public func cleanupOldSessions(olderThan days: Int = 7) throws {
        let sessions = try listSessions()
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))
        
        for session in sessions where session.timestamp < cutoffDate {
            try deleteSession(id: session.id)
        }
    }
    
    public func hasRecentSession() throws -> Bool {
        let sessions = try listSessions()
        return sessions.contains { $0.isRecent }
    }
}