import Foundation
import os.log

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

public final class XcalpLogger {
    public static let shared = XcalpLogger()
    
    private let logger: Logger
    private let dateFormatter: DateFormatter
    
    private init() {
        self.logger = Logger(subsystem: "com.xcalp.clinic", category: "General")
        
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    // MARK: - Logging Methods
    public func log(_ level: LogLevel, message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        
        switch level {
        case .debug:
            logger.debug("\(logMessage, privacy: .public)")
        case .info:
            logger.info("\(logMessage, privacy: .public)")
        case .warning:
            logger.warning("\(logMessage, privacy: .public)")
        case .error:
            logger.error("\(logMessage, privacy: .public)")
        case .critical:
            logger.critical("\(logMessage, privacy: .public)")
        }
        
        // Also save to file for HIPAA compliance
        saveToFile(logMessage)
    }
    
    // MARK: - HIPAA Compliance
    private func saveToFile(_ message: String) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let logsPath = documentsPath.appendingPathComponent("Logs")
        let dateString = DateFormatter().calendar.startOfDay(for: Date())
        let logFile = logsPath.appendingPathComponent("\(dateString)-clinic.log")
        
        do {
            // Create logs directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: logsPath.path) {
                try FileManager.default.createDirectory(at: logsPath, withIntermediateDirectories: true)
            }
            
            // Append log message to file
            if let data = (message + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    let fileHandle = try FileHandle(forWritingTo: logFile)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try data.write(to: logFile, options: .atomicWrite)
                }
            }
            
            // Rotate logs older than 30 days (HIPAA requirement)
            rotateOldLogs(in: logsPath)
        } catch {
            logger.error("Failed to save log to file: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func rotateOldLogs(in directory: URL) {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        
        do {
            let logFiles = try FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: [.creationDateKey],
                                                                     options: [.skipsHiddenFiles])
            
            for logFile in logFiles {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < thirtyDaysAgo {
                    try FileManager.default.removeItem(at: logFile)
                }
            }
        } catch {
            logger.error("Failed to rotate logs: \(error.localizedDescription, privacy: .public)")
        }
    }
}
